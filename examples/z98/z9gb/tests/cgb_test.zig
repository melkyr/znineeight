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
const ppumod = @import("../ppu.zig");
const cpumod = @import("../cpu.zig");

const ROM_BYTES: usize = 32768;
const PATH_MAX: usize = 256;

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_emu: emumod.Emu = undefined;
var g_ppu: ppumod.Ppu = undefined;
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

fn checkWord(label: []const u8, got: u16, want: u16) void {
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

fn checkU32(label: []const u8, got: u32, want: u32) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got & 0x00FFFFFF));
    std.io.write(" want=");
    printU(@intCast(usize, want & 0x00FFFFFF));
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

fn resetCgb() void {
    resetBus();
    g_bus.cgb_hw = true;
    g_bus.cgb_color = true;
    g_bus.cgb_compat = false;
    ppumod.ppuReset(&g_ppu);
    g_bus.io[0x0F] = 0;
}

fn setBgColor(pal: u8, color: u8, word: u16) void {
    const idx: u16 = @as(u16, pal) * 8 + @as(u16, color) * 2;
    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, @intCast(u8, (idx & 0x3F) | 0x80));
    mmumod.cgbPaletteWrite(&g_bus, 0xFF69, @intCast(u8, word & 0xFF));
    mmumod.cgbPaletteWrite(&g_bus, 0xFF69, @intCast(u8, (word >> 8) & 0xFF));
}

fn setObjColor(pal: u8, color: u8, word: u16) void {
    const idx: u16 = @as(u16, pal) * 8 + @as(u16, color) * 2;
    mmumod.cgbPaletteWrite(&g_bus, 0xFF6A, @intCast(u8, (idx & 0x3F) | 0x80));
    mmumod.cgbPaletteWrite(&g_bus, 0xFF6B, @intCast(u8, word & 0xFF));
    mmumod.cgbPaletteWrite(&g_bus, 0xFF6B, @intCast(u8, (word >> 8) & 0xFF));
}

fn setTileRowBank(bank: u8, tile: u8, row: usize, lo: u8, hi: u8) void {
    const base: usize = @as(usize, bank) * 0x2000 + @as(usize, tile) * 16 + row * 2;
    g_bus.vram[base] = lo;
    g_bus.vram[base + 1] = hi;
}

fn setBgAttr(tx: usize, attr: u8) void {
    g_bus.vram[0x2000 + 0x1800 + tx] = attr;
}

fn setSprite(index: usize, y: u8, x: u8, tile: u8, attr: u8) void {
    const o: usize = index * 4;
    g_bus.oam[o] = y;
    g_bus.oam[o + 1] = x;
    g_bus.oam[o + 2] = tile;
    g_bus.oam[o + 3] = attr;
}

fn testPaletteRam() void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);

    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, 0x85);
    checkByte("bcps index read", mmumod.cgbPaletteRead(&g_bus, 0xFF68), 0x85);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF69, 0x11);
    checkByte("bcps auto increment", mmumod.cgbPaletteRead(&g_bus, 0xFF68), 0x86);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF69, 0x22);
    checkByte("bcps auto increment 2", mmumod.cgbPaletteRead(&g_bus, 0xFF68), 0x87);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, 0x05);
    checkByte("bcpd latched 5", mmumod.cgbPaletteRead(&g_bus, 0xFF69), 0x11);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, 0x06);
    checkByte("bcpd latched 6", mmumod.cgbPaletteRead(&g_bus, 0xFF69), 0x22);

    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, 0x80);
    checkByte("bcpd read low", mmumod.cgbPaletteRead(&g_bus, 0xFF69), 0x00);
    checkByte("bcps read no increment", mmumod.cgbPaletteRead(&g_bus, 0xFF68), 0x80);

    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, 0x00);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF69, 0xFF);
    checkByte("bcpd full byte", mmumod.cgbPaletteRead(&g_bus, 0xFF69), 0xFF);

    mmumod.cgbPaletteWrite(&g_bus, 0xFF6A, 0x80 | 0x03);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF6B, 0x5A);
    checkByte("ocps auto increment", mmumod.cgbPaletteRead(&g_bus, 0xFF6A), 0x84);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF6A, 0x03);
    checkByte("ocpd latched", mmumod.cgbPaletteRead(&g_bus, 0xFF6B), 0x5A);
}

fn testPaletteColor() void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);

    setBgColor(0, 0, 0x7FFF);
    setBgColor(0, 1, 0x001F);
    setBgColor(0, 2, 0x03E0);
    setBgColor(0, 3, 0x7C00);
    g_bus.cram_rgb[4] = 0x00123456;
    setBgColor(0, 4, 0x0000);
    setObjColor(0, 0, 0x7FFF);

    checkU32("cram white", g_bus.cram_rgb[0], 0x00FFFFFF);
    checkU32("cram red", g_bus.cram_rgb[1], 0x00FF0000);
    checkU32("cram green", g_bus.cram_rgb[2], 0x0000FF00);
    checkU32("cram blue", g_bus.cram_rgb[3], 0x000000FF);
    checkU32("cram black", g_bus.cram_rgb[4], 0x00000000);
    checkU32("cram obj white", g_bus.cram_rgb[32], 0x00FFFFFF);
}

fn testDmgIgnoresCgbPalette() void {
    resetBus();
    mmumod.write8(&g_bus, 0xFF68, 0x00);
    mmumod.write8(&g_bus, 0xFF69, 0xFF);
    checkByte("dmg bcps reads ff", mmumod.read8(&g_bus, 0xFF68), 0xFF);
    checkByte("dmg bcpd reads ff", mmumod.read8(&g_bus, 0xFF69), 0xFF);
    checkByte("dmg bcpd ignored", g_bus.bcpd[0], 0x00);
    checkByte("dmg ocps reads ff", mmumod.read8(&g_bus, 0xFF6A), 0xFF);
    checkU32("dmg cram untouched", g_bus.cram_rgb[0], 0x00000000);

    resetBus();
    ppumod.ppuReset(&g_ppu);
    g_bus.cram_rgb[3] = 0x00FF0000;
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x91, &g_bus);
    ppumod.ppuWrite(&g_ppu, 0xFF47, 0xE4, &g_bus);
    setTileRowBank(0, 1, 0, 0xFF, 0xFF);
    g_bus.vram[0x1800] = 1;
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("dmg render ignores cgb", g_ppu.fb[0], 0x000F380F);
}

fn testPaletteMode3Block() void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setBgColor(0, 1, 0x001F);
    setObjColor(0, 1, 0x03E0);
    checkU32("cram before lock", g_bus.cram_rgb[1], 0x00FF0000);
    checkU32("obj cram before lock", g_bus.cram_rgb[33], 0x0000FF00);
    checkBool("palette unlocked reset", g_bus.ppu_palette_blocked, false);

    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkByte("palette mode3 entered", g_ppu.mode, 3);
    checkBool("palette blocked mode3", g_bus.ppu_palette_blocked, true);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF68, 0x82);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF69, 0xE0);
    checkByte("blocked bcps auto increment", mmumod.cgbPaletteRead(&g_bus, 0xFF68), 0x83);
    checkByte("blocked palette read", mmumod.cgbPaletteRead(&g_bus, 0xFF69), 0xFF);
    checkByte("blocked palette data", g_bus.bcpd[2], 0x1F);
    checkU32("blocked palette rgb", g_bus.cram_rgb[1], 0x00FF0000);

    mmumod.cgbPaletteWrite(&g_bus, 0xFF6A, 0x82);
    mmumod.cgbPaletteWrite(&g_bus, 0xFF6B, 0x00);
    checkByte("blocked ocps auto increment", mmumod.cgbPaletteRead(&g_bus, 0xFF6A), 0x83);
    checkByte("blocked ocpd read", mmumod.cgbPaletteRead(&g_bus, 0xFF6B), 0xFF);
    checkByte("blocked ocpd data", g_bus.ocpd[2], 0xE0);
    checkU32("blocked ocpd rgb", g_bus.cram_rgb[33], 0x0000FF00);

    ppumod.ppuTick(&g_ppu, g_ppu.mode3_len, &g_bus);
    checkByte("palette mode0 restored", g_ppu.mode, 0);
    checkBool("palette unlocked mode0", g_bus.ppu_palette_blocked, false);
    mmumod.write8(&g_bus, 0xFF68, 0x02);
    mmumod.write8(&g_bus, 0xFF69, 0xE0);
    checkByte("mode0 palette write", mmumod.read8(&g_bus, 0xFF69), 0xE0);
}

fn cgbBgBase(attr: u8) void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setBgColor(0, 0, 0x7C00);
    setBgColor(1, 0, 0x03E0);
    setBgColor(1, 1, 0x001F);
    setBgColor(1, 2, 0x7FFF);
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x91, &g_bus);
    g_bus.vram[0x1800] = 0;
    setTileRowBank(1, 0, 0, 0x80, 0x00);
    setBgAttr(0, 0x08 | 0x01 | attr);
}

fn testBgAttributes() void {
    cgbBgBase(0x00);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb bg bank1 palette", g_ppu.fb[0], 0x00FF0000);
    checkU32("cgb bg bank1 color0", g_ppu.fb[1], 0x0000FF00);

    cgbBgBase(0x20);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb bg xflip left", g_ppu.fb[0], 0x0000FF00);
    checkU32("cgb bg xflip right", g_ppu.fb[7], 0x00FF0000);

    cgbBgBase(0x40);
    setTileRowBank(1, 0, 7, 0x00, 0x80);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb bg yflip", g_ppu.fb[0], 0x00FFFFFF);

    cgbBgBase(0x10);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb bg attr bit4 ignored", g_ppu.fb[0], 0x00FF0000);
}

fn testCgbBgLcdcBit0() void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setBgColor(0, 1, 0x001F);
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x90, &g_bus);
    setTileRowBank(0, 1, 0, 0xFF, 0x00);
    g_bus.vram[0x1800] = 1;
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb bg shown lcdc0 clear", g_ppu.fb[0], 0x00FF0000);
}

fn testSpriteAttributes() void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setObjColor(2, 1, 0x001F);
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x93, &g_bus);
    setTileRowBank(1, 0, 0, 0x80, 0x00);
    setSprite(0, 16, 8, 0, 0x08 | 0x02);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb sprite bank1 palette", g_ppu.fb[0], 0x00FF0000);

    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setObjColor(2, 1, 0x001F);
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x93, &g_bus);
    setTileRowBank(1, 0, 0, 0x80, 0x00);
    setSprite(0, 16, 8, 0, 0x08 | 0x02 | 0x10);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb sprite attr bit4 ignored", g_ppu.fb[0], 0x00FF0000);
}

fn setupOamOrder() void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setObjColor(1, 1, 0x001F);
    setObjColor(2, 1, 0x03E0);
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x93, &g_bus);
    g_bus.vram[0x1800] = 1;
    setTileRowBank(0, 0, 0, 0xFF, 0x00);
    setSprite(0, 16, 9, 0, 0x01);
    setSprite(1, 16, 8, 0, 0x02);
}

fn testSpriteOamOrder() void {
    setupOamOrder();
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb sprite oam order", g_ppu.fb[1], 0x00FF0000);
    checkU32("cgb sprite higher oam only", g_ppu.fb[8], 0x00FF0000);

    setupOamOrder();
    mmumod.write8(&g_bus, 0xFF6C, 0x01);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
    checkU32("cgb sprite opri dmg x", g_ppu.fb[1], 0x0000FF00);
}

fn setupBgObj(bg_idx: u8, bg_prio: bool, lcdc_bg: bool, oam_behind: bool) void {
    resetCgb();
    mmumod.cgbPaletteReset(&g_bus);
    setBgColor(0, 0, 0x7C00);
    setBgColor(0, 1, 0x001F);
    setObjColor(0, 1, 0x03E0);
    const lcdc: u8 = 0x90 | 0x02 | (if (lcdc_bg) @as(u8, 1) else @as(u8, 0));
    ppumod.ppuWrite(&g_ppu, 0xFF40, lcdc, &g_bus);
    const bg_lo: u8 = if (bg_idx == 0) 0x00 else 0xFF;
    setTileRowBank(0, 1, 0, bg_lo, 0x00);
    setTileRowBank(0, 0, 0, 0xFF, 0x00);
    g_bus.vram[0x1800] = 1;
    setBgAttr(0, if (bg_prio) 0x80 else 0x00);
    setSprite(0, 16, 8, 0, if (oam_behind) 0x80 else 0x00);
    ppumod.ppuTick(&g_ppu, 84, &g_bus);
}

fn testBgObjPriority() void {
    setupBgObj(0, false, true, false);
    checkU32("cgb prio bg0 obj", g_ppu.fb[0], 0x0000FF00);

    setupBgObj(1, false, false, false);
    checkU32("cgb prio lcdc0 obj", g_ppu.fb[0], 0x0000FF00);

    setupBgObj(1, true, false, true);
    checkU32("cgb prio lcdc0 overrides attrs", g_ppu.fb[0], 0x0000FF00);

    setupBgObj(1, false, true, false);
    checkU32("cgb prio both clear obj", g_ppu.fb[0], 0x0000FF00);

    setupBgObj(1, true, true, false);
    checkU32("cgb prio bgattr bg", g_ppu.fb[0], 0x00FF0000);

    setupBgObj(1, false, true, true);
    checkU32("cgb prio oam behind bg", g_ppu.fb[0], 0x00FF0000);

    setupBgObj(1, true, true, true);
    checkU32("cgb prio both bg", g_ppu.fb[0], 0x00FF0000);
}

fn testOpriRead() void {
    resetCgb();
    mmumod.write8(&g_bus, 0xFF6C, 0x01);
    checkByte("opri cgb bit0", mmumod.read8(&g_bus, 0xFF6C), 0x01);
    mmumod.write8(&g_bus, 0xFF6C, 0xFE);
    checkByte("opri cgb high bits masked", mmumod.read8(&g_bus, 0xFF6C), 0x00);

    resetBus();
    g_bus.cgb_hw = true;
    g_bus.cgb_color = false;
    g_bus.cgb_compat = true;
    checkByte("opri compat read", mmumod.read8(&g_bus, 0xFF6C), 0x01);
    mmumod.write8(&g_bus, 0xFF6C, 0x00);
    checkByte("opri compat write ignored", mmumod.read8(&g_bus, 0xFF6C), 0x01);

    resetBus();
    checkByte("opri dmg read", mmumod.read8(&g_bus, 0xFF6C), 0xFF);
    mmumod.write8(&g_bus, 0xFF6C, 0x01);
    checkByte("opri dmg write ignored", mmumod.read8(&g_bus, 0xFF6C), 0xFF);
}

fn testCgbFramebuffer() void {
    resetCgb();
    const fb: []const u32 = ppumod.ppuCgbFramebuffer(&g_ppu);
    checkWord("cgb framebuffer length", @intCast(u16, fb.len), 23040);
    g_ppu.fb[0] = 0x00123456;
    checkU32("cgb framebuffer storage", fb[0], 0x00123456);
}

fn testSpeedSwitchRegisters() void {
    resetCgb();
    checkByte("key1 initial", mmumod.read8(&g_bus, 0xFF4D), 0x00);
    checkBool("speed initial normal", mmumod.cgbIsDoubleSpeed(&g_bus), false);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    checkByte("key1 armed", mmumod.read8(&g_bus, 0xFF4D), 0x01);
    mmumod.write8(&g_bus, 0xFF4D, 0x81);
    checkByte("key1 bit7 write ignored", mmumod.read8(&g_bus, 0xFF4D), 0x01);
    checkBool("speed switch returns true", mmumod.cgbSpeedSwitch(&g_bus), true);
    checkBool("double speed set", mmumod.cgbIsDoubleSpeed(&g_bus), true);
    checkByte("key1 double", mmumod.read8(&g_bus, 0xFF4D), 0x80);
    checkByte("key1 arm cleared", mmumod.read8(&g_bus, 0xFF4D) & 0x01, 0x00);
    checkBool("unarmed switch false", mmumod.cgbSpeedSwitch(&g_bus), false);
    checkBool("still double", mmumod.cgbIsDoubleSpeed(&g_bus), true);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    checkBool("switch back returns true", mmumod.cgbSpeedSwitch(&g_bus), true);
    checkByte("key1 normal", mmumod.read8(&g_bus, 0xFF4D), 0x00);

    resetBus();
    checkByte("dmg key1 reads ff", mmumod.read8(&g_bus, 0xFF4D), 0xFF);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    checkByte("dmg key1 write ignored", mmumod.read8(&g_bus, 0xFF4D), 0xFF);
    checkBool("dmg speed switch false", mmumod.cgbSpeedSwitch(&g_bus), false);
    checkBool("dmg stays normal", mmumod.cgbIsDoubleSpeed(&g_bus), false);

    resetBus();
    g_bus.cgb_hw = true;
    g_bus.cgb_color = false;
    g_bus.cgb_compat = true;
    checkByte("compat key1 reads ff", mmumod.read8(&g_bus, 0xFF4D), 0xFF);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    checkByte("compat key1 write ignored", mmumod.read8(&g_bus, 0xFF4D), 0xFF);
    checkBool("compat speed switch false", mmumod.cgbSpeedSwitch(&g_bus), false);
    checkBool("compat stays normal", mmumod.cgbIsDoubleSpeed(&g_bus), false);
}

const STOP_CODE: u16 = 0xC000;

fn initStopCpu(cpu: *cpumod.Cpu) void {
    cpumod.cpuInit(cpu);
    cpu.pc = STOP_CODE;
    cpu.sp = 0xFFFE;
    mmumod.write8(&g_bus, STOP_CODE, 0x10);
    mmumod.write8(&g_bus, STOP_CODE + 1, 0x00);
    mmumod.write8(&g_bus, STOP_CODE + 2, 0x00);
}

fn testStopSpeedSwitch() void {
    var cpu: cpumod.Cpu = undefined;

    resetCgb();
    initStopCpu(&cpu);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    const cyc: u32 = cpumod.cpuStep(&cpu, &g_bus);
    checkU32("stop switch cycles", cyc, 8200);
    checkWord("stop switch pc", cpu.pc, STOP_CODE + 2);
    checkBool("stop switch speed", mmumod.cgbIsDoubleSpeed(&g_bus), true);
    checkByte("stop switch key1", mmumod.read8(&g_bus, 0xFF4D), 0x80);
    checkWord("stop switch div frozen", g_bus.timer.divider, 4);
    checkBool("stop switch not idle", cpu.halted, false);
    checkU32("stop switch cpu cycles", @intCast(u32, cpu.cycles), 8200);

    cpu.pc = STOP_CODE;
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    const cyc2: u32 = cpumod.cpuStep(&cpu, &g_bus);
    checkU32("stop back cycles", cyc2, 8200);
    checkBool("stop back speed", mmumod.cgbIsDoubleSpeed(&g_bus), false);
    checkByte("stop back key1", mmumod.read8(&g_bus, 0xFF4D), 0x00);

    resetCgb();
    initStopCpu(&cpu);
    const cyc3: u32 = cpumod.cpuStep(&cpu, &g_bus);
    checkU32("plain stop cycles", cyc3, 4);
    checkBool("plain stop speed", mmumod.cgbIsDoubleSpeed(&g_bus), false);
    checkBool("plain stop idle", cpu.halted, true);

    resetBus();
    g_bus.cgb_hw = true;
    g_bus.cgb_color = false;
    g_bus.cgb_compat = true;
    initStopCpu(&cpu);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    const cyc4: u32 = cpumod.cpuStep(&cpu, &g_bus);
    checkU32("compat stop cycles", cyc4, 4);
    checkBool("compat stop speed", mmumod.cgbIsDoubleSpeed(&g_bus), false);
    checkBool("compat stop idle", cpu.halted, true);
    checkByte("compat stop key1", mmumod.read8(&g_bus, 0xFF4D), 0xFF);

    resetBus();
    initStopCpu(&cpu);
    const cyc5: u32 = cpumod.cpuStep(&cpu, &g_bus);
    checkU32("dmg stop cycles", cyc5, 4);
    checkBool("dmg stop speed", mmumod.cgbIsDoubleSpeed(&g_bus), false);
    checkBool("dmg stop idle", cpu.halted, true);
    checkByte("dmg stop key1", mmumod.read8(&g_bus, 0xFF4D), 0xFF);
}

fn testStopStallBus() void {
    resetCgb();
    const CODE: u16 = 0xFF90;
    mmumod.write8(&g_bus, CODE, 0x10);
    mmumod.write8(&g_bus, CODE + 1, 0x00);
    mmumod.write8(&g_bus, CODE + 2, 0x00);
    mmumod.write8(&g_bus, 0xFF01, 0x48);
    mmumod.write8(&g_bus, 0xFF02, 0x81);
    mmumod.write8(&g_bus, 0xFF4D, 0x01);
    mmumod.write8(&g_bus, 0xC100, 0xA5);
    mmumod.write8(&g_bus, 0xFF46, 0xC1);

    var cpu: cpumod.Cpu = undefined;
    cpumod.cpuInit(&cpu);
    cpu.pc = CODE;
    cpu.sp = 0xFFFE;
    const cyc: u32 = cpumod.cpuStep(&cpu, &g_bus);
    checkU32("stall stop cycles", cyc, 8200);
    checkBool("stall double speed", mmumod.cgbIsDoubleSpeed(&g_bus), true);
    checkWord("stall div frozen", g_bus.timer.divider, 4);
    checkU32("stall apu advanced", g_bus.apu.fs_cycles, 4102);
    checkWord("stall serial advanced", g_bus.serial.pending, 0);
    checkByte("stall serial irq", g_bus.io[0x0F] & 0x08, 0x08);
    checkByte("stall dma data", g_bus.oam[0], 0xA5);
    checkWord("stall dma index", g_bus.dma.index, 160);
    checkBool("stall dma done", g_bus.dma.active, false);
}

fn runTightLoop(double: bool) u32 {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = true, .serial_log = false, .turbo = false, .dynarec = false });
    g_emu.rom_len = 1;
    g_emu.bus.cgb_hw = true;
    g_emu.bus.cgb_color = true;
    g_emu.bus.double_speed = double;
    g_emu.bus.ie = 0;
    g_emu.bus.io[0x0F] = 0;
    mmumod.write8(&g_emu.bus, 0xC000, 0x18);
    mmumod.write8(&g_emu.bus, 0xC001, 0xFE);
    g_emu.cpu.pc = 0xC000;
    g_emu.cpu.sp = 0xFFFE;
    return emumod.emuRunFrame(&g_emu);
}

fn testDoubleSpeedTiming() void {
    const normal: u32 = runTightLoop(false);
    checkU32("normal frame cpu cycles", normal, 70224);
    checkWord("normal frame divider", g_emu.bus.timer.divider, 0x1250);
    checkU32("normal frame apu fs", g_emu.bus.apu.fs_cycles, 4688);
    checkByte("normal frame ppu line", g_emu.ppu.line, 0);
    checkU32("normal frame ppu dot", g_emu.ppu.dot, 0);

    const fast: u32 = runTightLoop(true);
    checkU32("double frame cpu cycles", fast, 140448);
    checkWord("double frame divider", g_emu.bus.timer.divider, 0x24A0);
    checkU32("double frame apu fs", g_emu.bus.apu.fs_cycles, 4688);
    checkByte("double frame ppu line", g_emu.ppu.line, 0);
    checkU32("double frame ppu dot", g_emu.ppu.dot, 0);
}

fn runMooneyeBreak(double: bool) u32 {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = true, .serial_log = false, .turbo = false, .dynarec = false });
    g_emu.rom_len = 1;
    g_emu.bus.cgb_hw = true;
    g_emu.bus.cgb_color = true;
    g_emu.bus.double_speed = double;
    g_emu.bus.ie = 0;
    g_emu.bus.io[0x0F] = 0;
    emumod.emuSetMooneye(&g_emu, true);
    mmumod.write8(&g_emu.bus, 0xC000, 0x06);
    mmumod.write8(&g_emu.bus, 0xC001, 0x02);
    mmumod.write8(&g_emu.bus, 0xC002, 0x05);
    mmumod.write8(&g_emu.bus, 0xC003, 0x20);
    mmumod.write8(&g_emu.bus, 0xC004, 0xFD);
    mmumod.write8(&g_emu.bus, 0xC005, 0x40);
    g_emu.cpu.pc = 0xC000;
    g_emu.cpu.sp = 0xFFFE;
    return emumod.emuRunFrame(&g_emu);
}

fn testDoubleSpeedPartialFrame() void {
    const normal: u32 = runMooneyeBreak(false);
    checkU32("partial normal cycles", normal, 36);
    checkByte("partial normal line", g_emu.ppu.line, 0);
    checkU32("partial normal dot", g_emu.ppu.dot, 36);

    const fast: u32 = runMooneyeBreak(true);
    checkU32("partial double cycles", fast, 36);
    checkByte("partial double line", g_emu.ppu.line, 0);
    checkU32("partial double dot", g_emu.ppu.dot, 18);
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
    testPaletteRam();
    testPaletteColor();
    testDmgIgnoresCgbPalette();
    testPaletteMode3Block();
    testBgAttributes();
    testCgbBgLcdcBit0();
    testSpriteAttributes();
    testSpriteOamOrder();
    testBgObjPriority();
    testOpriRead();
    testCgbFramebuffer();
    testSpeedSwitchRegisters();
    testStopSpeedSwitch();
    testStopStallBus();
    testDoubleSpeedTiming();
    testDoubleSpeedPartialFrame();

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
