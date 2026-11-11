// cgb_test.zig — CGB mode, VRAM/WRAM banking, and type-driven cart RAM policy.
//
// Run as a normal executable under both -ffast and -fsafe. argv[1] is a scratch
// directory for the temporary flagged ROMs. Every check is counted; the process
// exits 0 only when all checks pass.

const std = @import("std");
const filemod = @import("std_file");
const cartmod = @import("../cart.zig");
const mmumod = @import("../mmu.zig");
const emumod = @import("../emu.zig");

const ROM_BYTES: usize = 32768;
const PATH_MAX: usize = 256;

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_emu: emumod.Emu = undefined;
var g_rom: [ROM_BYTES]u8 = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

fn checkByte(label: []const u8, got: u8, want: u8) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkBool(label: []const u8, got: bool, want: bool) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write("\n");
}

fn copy(out: []u8, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) : (i += 1) out[i] = data[i];
}

fn joinPath(dir: []const u8, name: []const u8, out: []u8) []const u8 {
    const need: usize = dir.len + 1 + name.len;
    if (need > out.len) return "";
    copy(out[0..dir.len], dir);
    out[dir.len] = '/';
    copy(out[dir.len + 1 .. need], name);
    return out[0..need];
}

fn makeRom(typ: u8, cgb: u8, ramcode: u8) void {
    var i: usize = 0;
    while (i < ROM_BYTES) : (i += 1) g_rom[i] = 0;
    g_rom[0x0143] = cgb;
    g_rom[0x0147] = typ;
    g_rom[0x0148] = 0x00;
    g_rom[0x0149] = ramcode;
}

fn writeFlagRom(dir: []const u8, name: []const u8, cgb: u8, out: []u8) []const u8 {
    makeRom(0x00, cgb, 0x00);
    const path: []const u8 = joinPath(dir, name, out);
    filemod.writeAll(path, g_rom[0..]) catch {
        checkBool("write flag rom", false, true);
        return "";
    };
    return path;
}

fn resetBus() void {
    cartmod.cartInit(&g_cart);
    mmumod.busInit(&g_bus, &g_cart);
}

fn testVramBanks() void {
    resetBus();
    mmumod.mmuSetVramBank(&g_bus, 0);
    mmumod.write8(&g_bus, 0x8000, 0x11);
    mmumod.write8(&g_bus, 0x9FFF, 0x12);
    mmumod.mmuSetVramBank(&g_bus, 1);
    checkByte("vram bank1 starts clear", mmumod.read8(&g_bus, 0x8000), 0x00);
    mmumod.write8(&g_bus, 0x8000, 0x21);
    mmumod.write8(&g_bus, 0x9FFF, 0x22);
    checkByte("vram bank1 low", mmumod.read8(&g_bus, 0x8000), 0x21);
    checkByte("vram bank1 high", mmumod.read8(&g_bus, 0x9FFF), 0x22);
    mmumod.mmuSetVramBank(&g_bus, 0);
    checkByte("vram bank0 low", mmumod.read8(&g_bus, 0x8000), 0x11);
    checkByte("vram bank0 high", mmumod.read8(&g_bus, 0x9FFF), 0x12);
    mmumod.mmuSetVramBank(&g_bus, 2);
    checkByte("vram bank masks bit0", mmumod.mmuVramBank(&g_bus), 0);
}

fn testWramBanks() void {
    resetBus();
    mmumod.write8(&g_bus, 0xC000, 0xA0);
    var bank: u8 = 1;
    while (bank < 8) : (bank += 1) {
        mmumod.mmuSetWramBank(&g_bus, bank);
        mmumod.write8(&g_bus, 0xD000, 0x40 + bank);
        mmumod.write8(&g_bus, 0xDFFF, 0x50 + bank);
    }
    bank = 1;
    while (bank < 8) : (bank += 1) {
        mmumod.mmuSetWramBank(&g_bus, bank);
        checkByte("wram bank low", mmumod.read8(&g_bus, 0xD000), 0x40 + bank);
        checkByte("wram bank high", mmumod.read8(&g_bus, 0xDFFF), 0x50 + bank);
        checkByte("wram c000 fixed", mmumod.read8(&g_bus, 0xC000), 0xA0);
        checkByte("wram echo c000", mmumod.read8(&g_bus, 0xE000), 0xA0);
        checkByte("wram echo d000", mmumod.read8(&g_bus, 0xF000), 0x40 + bank);
    }
    mmumod.mmuSetWramBank(&g_bus, 0);
    checkByte("svbk zero maps bank1", mmumod.mmuWramBank(&g_bus), 1);
    checkByte("svbk zero data", mmumod.read8(&g_bus, 0xD000), 0x41);
}

fn testBankRegisters() void {
    resetBus();
    g_bus.cgb_hw = true;
    g_bus.cgb_color = true;
    g_bus.cgb_compat = false;

    mmumod.write8(&g_bus, 0xFF4F, 1);
    checkByte("vbk selects bank1", mmumod.mmuVramBank(&g_bus), 1);
    mmumod.write8(&g_bus, 0x8000, 0x99);
    mmumod.write8(&g_bus, 0xFF4F, 0xFE);
    checkByte("vbk bit0 only", mmumod.mmuVramBank(&g_bus), 0);
    checkByte("vbk bank0 intact", mmumod.read8(&g_bus, 0x8000), 0x00);

    mmumod.write8(&g_bus, 0xFF70, 0);
    checkByte("svbk reg zero maps bank1", mmumod.mmuWramBank(&g_bus), 1);
    mmumod.write8(&g_bus, 0xFF70, 5);
    checkByte("svbk reg bank5", mmumod.mmuWramBank(&g_bus), 5);
    mmumod.write8(&g_bus, 0xFF70, 0xFA);
    checkByte("svbk reg bits 0-2", mmumod.mmuWramBank(&g_bus), 2);

    resetBus();
    g_bus.cgb_hw = true;
    g_bus.cgb_color = false;
    g_bus.cgb_compat = true;
    mmumod.write8(&g_bus, 0xFF4F, 1);
    mmumod.write8(&g_bus, 0xFF70, 5);
    checkByte("compat vbk inactive", mmumod.mmuVramBank(&g_bus), 0);
    checkByte("compat svbk inactive", mmumod.mmuWramBank(&g_bus), 1);

    resetBus();
    mmumod.write8(&g_bus, 0xFF4F, 1);
    mmumod.write8(&g_bus, 0xFF70, 5);
    checkByte("dmg vbk inactive", mmumod.mmuVramBank(&g_bus), 0);
    checkByte("dmg svbk inactive", mmumod.mmuWramBank(&g_bus), 1);
}

fn testCartModes() void {
    makeRom(0x00, 0xC0, 0x00);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("c0 cart load", false, true);
    };
    checkBool("c0 mode", cartmod.cgbMode(&g_cart) == .cgb_only, true);

    makeRom(0x00, 0x80, 0x00);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("80 cart load", false, true);
    };
    checkBool("80 mode", cartmod.cgbMode(&g_cart) == .cgb_compatible, true);

    makeRom(0x00, 0x00, 0x00);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("00 cart load", false, true);
    };
    checkBool("00 mode", cartmod.cgbMode(&g_cart) == .dmg, true);
}

fn loadEmu(path: []const u8, cgb: bool) emumod.EmuError!void {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = cgb, .serial_log = false, .turbo = true, .dynarec = false });
    try emumod.emuLoadRom(&g_emu, path);
}

fn testEmuModes(dir: []const u8) void {
    var path_buf: [PATH_MAX]u8 = undefined;
    const c0: []const u8 = writeFlagRom(dir, "flag_c0.gb", 0xC0, path_buf[0..]);

    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = true, .dynarec = false });
    var required: bool = false;
    emumod.emuLoadRom(&g_emu, c0) catch |err| {
        if (err == error.CgbRequired) required = true;
    };
    checkBool("c0 rejects dmg", required, true);

    loadEmu(c0, true) catch {
        checkBool("c0 loads cgb", false, true);
    };
    checkBool("c0 cgb hw", g_emu.bus.cgb_hw, true);
    checkBool("c0 cgb color", g_emu.bus.cgb_color, true);
    checkBool("c0 cgb compat", g_emu.bus.cgb_compat, false);
    emumod.emuReset(&g_emu);
    checkBool("c0 reset hw", g_emu.bus.cgb_hw, true);
    checkBool("c0 reset color", g_emu.bus.cgb_color, true);
    checkBool("c0 reset compat", g_emu.bus.cgb_compat, false);

    const c80: []const u8 = writeFlagRom(dir, "flag_80.gb", 0x80, path_buf[0..]);
    loadEmu(c80, false) catch {
        checkBool("80 loads dmg", false, true);
    };
    checkBool("80 dmg hw", g_emu.bus.cgb_hw, false);
    checkBool("80 dmg color", g_emu.bus.cgb_color, false);
    checkBool("80 dmg compat", g_emu.bus.cgb_compat, false);

    loadEmu(c80, true) catch {
        checkBool("80 loads cgb", false, true);
    };
    checkBool("80 cgb hw", g_emu.bus.cgb_hw, true);
    checkBool("80 cgb color", g_emu.bus.cgb_color, true);
    checkBool("80 cgb compat", g_emu.bus.cgb_compat, false);

    const plain: []const u8 = writeFlagRom(dir, "flag_00.gb", 0x00, path_buf[0..]);
    loadEmu(plain, true) catch {
        checkBool("00 loads cgb compat", false, true);
    };
    checkBool("00 compat hw", g_emu.bus.cgb_hw, true);
    checkBool("00 compat color", g_emu.bus.cgb_color, false);
    checkBool("00 compat flag", g_emu.bus.cgb_compat, true);
    mmumod.write8(&g_emu.bus, 0xFF70, 5);
    mmumod.write8(&g_emu.bus, 0xFF4F, 1);
    checkByte("00 compat svbk inactive", mmumod.mmuWramBank(&g_emu.bus), 1);
    checkByte("00 compat vbk inactive", mmumod.mmuVramBank(&g_emu.bus), 0);

    loadEmu(plain, false) catch {
        checkBool("00 loads dmg", false, true);
    };
    checkBool("00 dmg hw", g_emu.bus.cgb_hw, false);
    checkBool("00 dmg color", g_emu.bus.cgb_color, false);
    checkBool("00 dmg compat", g_emu.bus.cgb_compat, false);
}

fn testRamInference() void {
    makeRom(0x02, 0x00, 0x00);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("ram infer load", false, true);
    };
    checkByte("ram infer size low", @intCast(u8, cartmod.cartRamSize(&g_cart) & 0xFF), 0x00);
    checkByte("ram infer size high", @intCast(u8, (cartmod.cartRamSize(&g_cart) >> 8) & 0xFF), 0x20);
    checkBool("ram infer flag", g_cart.ram_inferred, true);
    mmumod.busInit(&g_bus, &g_cart);
    mmumod.write8(&g_bus, 0x0000, 0x0A);
    mmumod.write8(&g_bus, 0xA000, 0x77);
    mmumod.write8(&g_bus, 0xBFFF, 0x88);
    checkByte("ram infer write a000", mmumod.read8(&g_bus, 0xA000), 0x77);
    checkByte("ram infer write bfff", mmumod.read8(&g_bus, 0xBFFF), 0x88);

    makeRom(0x01, 0x00, 0x00);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("no ram load", false, true);
    };
    checkBool("no ram size", cartmod.cartRamSize(&g_cart) == 0, true);
    checkBool("no ram inferred", g_cart.ram_inferred, false);
    mmumod.busInit(&g_bus, &g_cart);
    mmumod.write8(&g_bus, 0x0000, 0x0A);
    mmumod.write8(&g_bus, 0xA000, 0x77);
    checkByte("no ram unmapped", mmumod.read8(&g_bus, 0xA000), 0xFF);

    makeRom(0x02, 0x00, 0x02);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("ram declared load", false, true);
    };
    checkBool("ram declared size", cartmod.cartRamSize(&g_cart) == 8192, true);
    checkBool("ram declared inferred", g_cart.ram_inferred, false);

    makeRom(0x19, 0x00, 0x04);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("strict mbc5 no ram load", false, true);
    };
    checkBool("strict mbc5 no ram size", cartmod.cartRamSize(&g_cart) == 0, true);
    checkBool("strict mbc5 no ram inferred", g_cart.ram_inferred, false);
    mmumod.busInit(&g_bus, &g_cart);
    mmumod.write8(&g_bus, 0x0000, 0x0A);
    mmumod.write8(&g_bus, 0xA000, 0x77);
    mmumod.write8(&g_bus, 0xBFFF, 0x88);
    checkByte("strict mbc5 a000 unmapped", mmumod.read8(&g_bus, 0xA000), 0xFF);
    checkByte("strict mbc5 bfff unmapped", mmumod.read8(&g_bus, 0xBFFF), 0xFF);

    makeRom(0x1A, 0x00, 0x04);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch {
        checkBool("mbc5 ram load", false, true);
    };
    checkBool("mbc5 ram size", cartmod.cartRamSize(&g_cart) == 131072, true);
    checkBool("mbc5 ram inferred", g_cart.ram_inferred, false);
    mmumod.busInit(&g_bus, &g_cart);
    mmumod.write8(&g_bus, 0x0000, 0x0A);
    mmumod.write8(&g_bus, 0x4000, 2);
    mmumod.write8(&g_bus, 0xA000, 0x2A);
    mmumod.write8(&g_bus, 0x4000, 5);
    mmumod.write8(&g_bus, 0xA000, 0x5A);
    mmumod.write8(&g_bus, 0x4000, 2);
    checkByte("mbc5 ram bank2", mmumod.read8(&g_bus, 0xA000), 0x2A);
    mmumod.write8(&g_bus, 0x4000, 5);
    checkByte("mbc5 ram bank5", mmumod.read8(&g_bus, 0xA000), 0x5A);

    makeRom(0x05, 0x00, 0x00);
    cartmod.cartInit(&g_cart);
    var mbc2_unsupported: bool = false;
    cartmod.cartLoad(&g_cart, g_rom[0..]) catch |err| {
        if (err == error.UnsupportedMbc) mbc2_unsupported = true;
    };
    checkBool("mbc2 exempt unsupported", mbc2_unsupported, true);
    checkBool("mbc2 exempt no inference", g_cart.ram_size == 0 and !g_cart.ram_inferred, true);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    if (argc < 2) {
        std.io.write("cgb FAIL no scratch dir\n");
        std.os.exit(2);
    }
    const p: [*]const u8 = @ptrCast([*]const u8, argv[1]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    const dir: []const u8 = p[0..n];

    testVramBanks();
    testWramBanks();
    testBankRegisters();
    testCartModes();
    testEmuModes(dir);
    testRamInference();

    if (g_fail == 0) {
        std.io.write("cgb ok ");
        printU(@intCast(usize, g_pass));
        std.io.write(" checks\n");
        std.os.exit(0);
    }
    std.io.write("FAIL ");
    printU(@intCast(usize, g_fail));
    std.io.write(" failed, ");
    printU(@intCast(usize, g_pass));
    std.io.write(" passed\n");
    std.os.exit(1);
}
