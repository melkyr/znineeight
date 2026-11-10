// emu.zig — z9gb Emu facade (P1: fixed storage + deterministic framebuffer).
//
// Pure Z98 free functions only. The 8 MiB ROM buffer lives inside `Emu`; the
// single instance must be a module-scope `var` (never a stack local and never a
// by-value copy) so the 1 MiB stack is never touched. No heap allocation.

const std = @import("std");
const filemod = @import("std_file");
const cartmod = @import("cart.zig");
const mmumod = @import("mmu.zig");
const cpumod = @import("cpu.zig");
const serialmod = @import("serial.zig");
const ppumod = @import("ppu.zig");
const savemod = @import("save.zig");

const ROM_CAP: usize = 8 * 1024 * 1024;
const SAVE_CAP: usize = 260;
const FRAME_W: usize = 160;
const FRAME_H: usize = 144;

pub const EmuConfig = struct { cgb: bool, serial_log: bool, turbo: bool, dynarec: bool };

pub const EmuError = error{ RomTooLarge, BadHeader, UnsupportedMbc, CgbRequired, SaveCorrupt, Io, OutOfMemory };

pub const Emu = struct {
    rom: [ROM_CAP]u8,
    rom_len: usize,
    buttons: u8,
    cfg: EmuConfig,
    save_path: [SAVE_CAP]u8,
    save_len: usize,
    rom_path: [SAVE_CAP]u8,
    rom_path_len: usize,
    cart: cartmod.Cart,
    cpu: cpumod.Cpu,
    bus: mmumod.Bus,
    ppu: ppumod.Ppu,
    mooneye: bool,
    mooneye_stopped: bool,
    mooneye_sig: [6]u8,
};

pub fn emuInit(e: *Emu, cfg: EmuConfig) void {
    // Scalar fields only: a whole-`Emu` literal would materialize an ~8.5 MiB
    // temporary on the 1 MiB stack. `rom`, the PPU framebuffer, and `save_path` are fixed
    // storage written by their owners.
    e.rom_len = 0;
    e.buttons = 0;
    e.cfg = cfg;
    e.save_len = 0;
    e.rom_path_len = 0;
    cartmod.cartInit(&e.cart);
    mmumod.busInit(&e.bus, &e.cart);
    cpumod.cpuInit(&e.cpu);
    ppumod.ppuReset(&e.ppu);
    e.mooneye = false;
    e.mooneye_stopped = false;
    var mi: usize = 0;
    while (mi < 6) : (mi += 1) e.mooneye_sig[mi] = 0;
}

// Loader contract: size-checked copy into the fixed 8 MiB buffer, then validate
// and re-point the cartridge windows from that buffer.
pub fn emuLoadRom(e: *Emu, path: []const u8) EmuError!void {
    var arena_buf: [1]u8 = undefined;
    var arena = std.arena.init(arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch return error.Io;
    var sz = filemod.size(&f) catch {
        filemod.close(&f);
        return error.Io;
    };
    if (sz < 0) {
        filemod.close(&f);
        return error.Io;
    }
    // Check the full i64 size before narrowing: on the pinned -m32 target a
    // file >= 4 GiB would truncate (exactly 4 GiB to n=0) and slip past a
    // post-narrow cap check.
    if (sz > @intCast(i64, ROM_CAP)) {
        filemod.close(&f);
        return error.RomTooLarge;
    }
    const n: usize = @intCast(usize, sz);
    var got: usize = 0;
    while (got < n) {
        const r = filemod.read(&f, e.rom[got..n]) catch {
            filemod.close(&f);
            return error.Io;
        };
        if (r == 0) break;
        got += r;
    }
    filemod.close(&f);
    if (got != n) return error.Io;
    e.rom_len = got;
    cartmod.cartLoad(&e.cart, e.rom[0..e.rom_len]) catch |err| {
        return switch (err) {
            error.BadHeader => error.BadHeader,
            error.UnsupportedMbc => error.UnsupportedMbc,
            error.RomTooLarge => error.RomTooLarge,
            error.Io => error.Io,
            else => error.Io,
        };
    };
    var rp: usize = path.len;
    if (rp > SAVE_CAP) rp = SAVE_CAP;
    var ri: usize = 0;
    while (ri < rp) : (ri += 1) {
        e.rom_path[ri] = path[ri];
    }
    e.rom_path_len = rp;
    mmumod.busInit(&e.bus, &e.cart);
}

pub fn emuReset(e: *Emu) void {
    e.buttons = 0;
    mmumod.busInit(&e.bus, &e.cart);
    cpumod.cpuInit(&e.cpu);
    ppumod.ppuReset(&e.ppu);
    e.ppu.ly = 0x91;
    e.ppu.line = 0x91;
    e.ppu.dot = 0;
    e.ppu.mode = 1;
    e.cpu.a = 0x01;
    e.cpu.f = 0xB0;
    e.cpu.b = 0x00;
    e.cpu.c = 0x13;
    e.cpu.d = 0x00;
    e.cpu.e = 0xD8;
    e.cpu.h = 0x01;
    e.cpu.l = 0x4D;
    e.cpu.sp = 0xFFFE;
    e.cpu.pc = 0x0100;
}

pub fn emuSelfTestPattern(e: *Emu) void {
    const p: *ppumod.Ppu = &e.ppu;
    var y: usize = 0;
    while (y < FRAME_H) : (y += 1) {
        var x: usize = 0;
        while (x < FRAME_W) : (x += 1) {
            p.fb[y * FRAME_W + x] = 0x00010000 | @intCast(u32, x & 0xFF) | (@intCast(u32, y & 0xFF) << 8);
        }
    }
}

fn ppuSyncIn(e: *Emu) void {
    ppumod.ppuWrite(&e.ppu, 0xFF40, e.bus.io[0x40], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF41, e.bus.io[0x41], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF42, e.bus.io[0x42], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF43, e.bus.io[0x43], &e.bus);
    if (e.bus.lyc_dirty or e.bus.io[0x45] != e.ppu.lyc) {
        e.bus.lyc_dirty = false;
        ppumod.ppuWrite(&e.ppu, 0xFF45, e.bus.io[0x45], &e.bus);
    }
    ppumod.ppuWrite(&e.ppu, 0xFF46, e.bus.io[0x46], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF47, e.bus.io[0x47], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF48, e.bus.io[0x48], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF49, e.bus.io[0x49], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF4A, e.bus.io[0x4A], &e.bus);
    ppumod.ppuWrite(&e.ppu, 0xFF4B, e.bus.io[0x4B], &e.bus);
}

fn ppuSyncOut(e: *Emu) void {
    e.bus.io[0x41] = ppumod.ppuRead(&e.ppu, 0xFF41);
    e.bus.io[0x44] = ppumod.ppuRead(&e.ppu, 0xFF44);
}

pub fn emuRunFrame(e: *Emu) u32 {
    if (e.rom_len == 0) {
        emuSelfTestPattern(e);
        return 70224;
    }
    if (e.mooneye_stopped) return 0;
    var total: u32 = 0;
    while (total < 70224) {
        // Mooneye magic breakpoint: stop before executing `LD B,B` (0x40).
        // The test has already loaded the full Fibonacci signature into
        // B/C/D/E/H/L; a present 0x40 on the instruction stream is the signal.
        if (e.mooneye and !e.cpu.halted and mmumod.read8(&e.bus, e.cpu.pc) == 0x40) {
            e.mooneye_sig[0] = e.cpu.b;
            e.mooneye_sig[1] = e.cpu.c;
            e.mooneye_sig[2] = e.cpu.d;
            e.mooneye_sig[3] = e.cpu.e;
            e.mooneye_sig[4] = e.cpu.h;
            e.mooneye_sig[5] = e.cpu.l;
            e.mooneye_stopped = true;
            return total;
        }
        const cycles: u32 = cpumod.cpuStep(&e.cpu, &e.bus);
        total += cycles;
        ppuSyncIn(e);
        ppumod.ppuTick(&e.ppu, cycles, &e.bus);
        ppuSyncOut(e);
    }
    return total;
}

pub fn emuFramebuffer(e: *const Emu) []const u32 {
    return ppumod.ppuFramebuffer(&e.ppu);
}

pub fn emuSetButtons(e: *Emu, bits: u8) void {
    e.buttons = bits;
}

pub fn emuSetMooneye(e: *Emu, enabled: bool) void {
    e.mooneye = enabled;
    e.mooneye_stopped = false;
}

pub fn emuMooneyeStopped(e: *const Emu) bool {
    return e.mooneye_stopped;
}

pub fn emuMooneyeSignature(e: *const Emu, out: []u8) void {
    var i: usize = 0;
    while (i < 6 and i < out.len) : (i += 1) out[i] = e.mooneye_sig[i];
}

pub fn emuMooneyePass(e: *const Emu) bool {
    if (!e.mooneye_stopped) return false;
    return e.mooneye_sig[0] == 3 and
        e.mooneye_sig[1] == 5 and
        e.mooneye_sig[2] == 8 and
        e.mooneye_sig[3] == 13 and
        e.mooneye_sig[4] == 21 and
        e.mooneye_sig[5] == 34;
}

pub fn emuTakeSerial(e: *Emu, out: []u8) usize {
    return serialmod.serialTake(&e.bus.serial, out);
}

pub fn emuSetSavePath(e: *Emu, path: []const u8) void {
    var n: usize = path.len;
    if (n > SAVE_CAP) n = SAVE_CAP;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        e.save_path[i] = path[i];
    }
    e.save_len = n;
}

// Frozen RTC epoch for deterministic headless tests (`EmuConfig.rtc_fixed`
// wiring lands with the Task 9 CLI). The first call anchors the counters; later
// calls advance the frozen clock.
pub fn emuSetRtcFixed(e: *Emu, unix: i64) void {
    cartmod.rtcSetFixed(&e.cart, unix);
}

pub fn emuSaveBattery(e: *Emu) EmuError!void {
    if (e.save_len != 0) return savemod.saveBattery(e, e.save_path[0..e.save_len]);
    if (e.rom_path_len != 0) return savemod.saveBattery(e, e.rom_path[0..e.rom_path_len]);
    return error.Io;
}

pub fn emuLoadBattery(e: *Emu) EmuError!void {
    if (e.save_len != 0) return savemod.loadBattery(e, e.save_path[0..e.save_len]);
    if (e.rom_path_len != 0) return savemod.loadBattery(e, e.rom_path[0..e.rom_path_len]);
    return error.Io;
}
