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
const apumod = @import("apu.zig");
const dynarecmod = @import("dynarec/dynarec.zig");

const ROM_CAP: usize = 8 * 1024 * 1024;
const SAVE_CAP: usize = 260;
const FRAME_W: usize = 160;
const FRAME_H: usize = 144;

// One DMG frame at the 4,194,304 Hz master clock. main.zig uses the same
// constant for the QPC deadline (70224 * freq / 4194304).
pub const FRAME_CYCLES: u32 = 70224;

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
    // Stable storage for the generated-code cache: the glue embeds absolute
    // addresses of Dynarec fields, so this must never be a temporary/copy.
    dynarec: dynarecmod.Dynarec,
    ppu: ppumod.Ppu,
    mooneye: bool,
    mooneye_stopped: bool,
    mooneye_sig: [6]u8,
};

pub fn emuInit(e: *Emu, cfg: EmuConfig) void {
    // Scalar fields only: a whole-`Emu` literal would materialize an ~8.5 MiB
    // temporary on the 1 MiB stack. `rom`, the PPU framebuffer, and `save_path` are fixed
    // storage written by their owners.
    // A zeroed static Emu starts with mapped=false. Re-initializing one that
    // still owns a code-cache mapping must release it before resetting state,
    // otherwise the 1 MiB VirtualAlloc/mmap pointer is lost.
    if (e.dynarec.mapped) dynarecmod.dynarecClose(&e.dynarec);
    e.rom_len = 0;
    e.buttons = 0;
    e.cfg = cfg;
    e.save_len = 0;
    e.rom_path_len = 0;
    cartmod.cartInit(&e.cart);
    mmumod.busInit(&e.bus, &e.cart);
    cpumod.cpuInit(&e.cpu);
    ppumod.ppuReset(&e.ppu);
    e.dynarec.mapped = false;
    e.dynarec.stats = dynarecmod.Stats{ .blocks = 0, .executed = 0, .chained = 0, .fallback = 0, .resets = 0, .collisions = 0 };
    dynarecmod.dynarecFlush(&e.dynarec);
    _ = emuSetDynarec(e, cfg.dynarec);
    e.mooneye = false;
    e.mooneye_stopped = false;
    var mi: usize = 0;
    while (mi < 6) : (mi += 1) e.mooneye_sig[mi] = 0;
}

// The dynarec is Win32/x86 only. `--dynarec` on any other host must hard-gate
// to the interpreter instead of exposing the test-only RWX mmap mapping.
pub fn emuSetDynarec(e: *Emu, on: bool) bool {
    e.cfg.dynarec = on;
    if (!on) {
        if (dynarecmod.dynarecEnabled(&e.dynarec)) dynarecmod.dynarecClose(&e.dynarec);
        return false;
    }
    if (!@isWindows()) {
        if (dynarecmod.dynarecEnabled(&e.dynarec)) dynarecmod.dynarecClose(&e.dynarec);
        return false;
    }
    if (dynarecmod.dynarecEnabled(&e.dynarec)) return true;
    _ = dynarecmod.dynarecOpen(&e.dynarec, &e.bus);
    return dynarecmod.dynarecEnabled(&e.dynarec);
}

pub fn emuDynarecEnabled(e: *const Emu) bool {
    return e.cfg.dynarec and dynarecmod.dynarecEnabled(&e.dynarec);
}

pub const DynarecStats = struct { blocks: u32, executed: u32, fallback: u32 };

pub fn emuDynarecStats(e: *const Emu) DynarecStats {
    const dynp: *const dynarecmod.Dynarec = &e.dynarec;
    return DynarecStats{ .blocks = dynp.stats.blocks, .executed = dynp.stats.executed, .fallback = dynp.stats.fallback };
}

fn applyCgbMode(e: *Emu) void {
    const mode = cartmod.cgbMode(&e.cart);
    e.bus.cgb_hw = e.cfg.cgb;
    e.bus.cgb_color = e.cfg.cgb and mode != .dmg;
    e.bus.cgb_compat = e.cfg.cgb and mode == .dmg;
    apumod.apuSetCgb(&e.bus.apu, e.bus.cgb_color);
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
    if (cartmod.cgbMode(&e.cart) == .cgb_only and !e.cfg.cgb) return error.CgbRequired;
    var rp: usize = path.len;
    if (rp > SAVE_CAP) rp = SAVE_CAP;
    var ri: usize = 0;
    while (ri < rp) : (ri += 1) {
        e.rom_path[ri] = path[ri];
    }
    e.rom_path_len = rp;
    mmumod.busInit(&e.bus, &e.cart);
    if (dynarecmod.dynarecEnabled(&e.dynarec)) dynarecmod.dynarecFlush(&e.dynarec);
    applyCgbMode(e);
}

pub fn emuReset(e: *Emu) void {
    e.buttons = 0;
    mmumod.busInit(&e.bus, &e.cart);
    applyCgbMode(e);
    cpumod.cpuInit(&e.cpu);
    ppumod.ppuReset(&e.ppu);
    e.ppu.ly = 0x91;
    e.ppu.line = 0x91;
    e.ppu.dot = 0;
    e.ppu.mode = 1;
    if (e.bus.cgb_hw) {
        e.cpu.a = 0x11;
        e.cpu.f = 0x80;
        e.cpu.b = 0x00;
        e.cpu.c = 0x00;
        e.cpu.d = 0xFF;
        e.cpu.e = 0x56;
        e.cpu.h = 0x00;
        e.cpu.l = 0x0D;
    } else {
        e.cpu.a = 0x01;
        e.cpu.f = 0xB0;
        e.cpu.b = 0x00;
        e.cpu.c = 0x13;
        e.cpu.d = 0x00;
        e.cpu.e = 0xD8;
        e.cpu.h = 0x01;
        e.cpu.l = 0x4D;
    }
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
    const b: *mmumod.Bus = &e.bus;
    ppumod.ppuWrite(&e.ppu, 0xFF40, b.io[0x40], b);
    ppumod.ppuWrite(&e.ppu, 0xFF41, b.io[0x41], b);
    ppumod.ppuWrite(&e.ppu, 0xFF42, b.io[0x42], b);
    ppumod.ppuWrite(&e.ppu, 0xFF43, b.io[0x43], b);
    if (b.lyc_dirty or b.io[0x45] != e.ppu.lyc) {
        b.lyc_dirty = false;
        ppumod.ppuWrite(&e.ppu, 0xFF45, b.io[0x45], b);
    }
    ppumod.ppuWrite(&e.ppu, 0xFF46, b.io[0x46], b);
    ppumod.ppuWrite(&e.ppu, 0xFF47, b.io[0x47], b);
    ppumod.ppuWrite(&e.ppu, 0xFF48, b.io[0x48], b);
    ppumod.ppuWrite(&e.ppu, 0xFF49, b.io[0x49], b);
    ppumod.ppuWrite(&e.ppu, 0xFF4A, b.io[0x4A], b);
    ppumod.ppuWrite(&e.ppu, 0xFF4B, b.io[0x4B], b);
}

fn ppuSyncOut(e: *Emu) void {
    const b: *mmumod.Bus = &e.bus;
    b.io[0x41] = ppumod.ppuRead(&e.ppu, 0xFF41);
    b.io[0x44] = ppumod.ppuRead(&e.ppu, 0xFF44);
}

// A cart-control write ends the containing block, but a block may still hold
// the write itself (static or dynamic stores). Compare the effective cart bank
// offsets around both dispatch paths and drop the affected ROM window.
fn invalidateChangedBanks(e: *Emu, rom0: usize, romx: usize) void {
    const cartp: *const cartmod.Cart = &e.cart;
    const dynp: *dynarecmod.Dynarec = &e.dynarec;
    if (!dynarecmod.dynarecEnabled(dynp)) return;
    if (cartp.rom0_off != rom0) dynarecmod.dynarecInvalidateRom0(dynp);
    if (cartp.romx_off != romx) dynarecmod.dynarecInvalidateRomx(dynp);
}

fn dynarecEligible(e: *const Emu) bool {
    const cpup: *const cpumod.Cpu = &e.cpu;
    const busp: *const mmumod.Bus = &e.bus;
    const dynp: *const dynarecmod.Dynarec = &e.dynarec;
    if (!@isWindows()) return false;
    if (!e.cfg.dynarec) return false;
    if (!dynarecmod.dynarecEnabled(dynp)) return false;

    if (cpup.halted or cpup.halt_bug) return false;
    if (cpup.ei_delay != 0) return false;
    if (busp.dma.active) return false;
    if (busp.hdma.cpu_halt_cycles != 0) return false;
    if (cpup.pc > 0x7FFF) return false;
    if (cpumod.cpuInterruptPending(cpup, busp)) return false;
    return true;
}

fn interpreterStep(e: *Emu) u32 {
    const cartp: *const cartmod.Cart = &e.cart;
    const dynp: *dynarecmod.Dynarec = &e.dynarec;
    const cpup: *cpumod.Cpu = &e.cpu;
    const busp: *mmumod.Bus = &e.bus;
    const rom0: usize = cartp.rom0_off;
    const romx: usize = cartp.romx_off;
    const cycles: u32 = cpumod.cpuStep(cpup, busp);
    if (dynarecmod.dynarecEnabled(dynp)) dynp.stats.fallback +%= 1;
    invalidateChangedBanks(e, rom0, romx);
    return cycles;
}

pub fn emuRunFrame(e: *Emu) u32 {
    if (e.rom_len == 0) {
        emuSelfTestPattern(e);
        return FRAME_CYCLES;
    }
    if (e.mooneye_stopped) return 0;
    var total: u32 = 0;
    var dots: u32 = 0;
    while (dots < FRAME_CYCLES) {
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
        var cycles: u32 = 0;
        if (dynarecEligible(e)) {
            const cartp: *const cartmod.Cart = &e.cart;
            const dynp: *dynarecmod.Dynarec = &e.dynarec;
            const cpup: *cpumod.Cpu = &e.cpu;
            const busp: *mmumod.Bus = &e.bus;
            const rom0: usize = cartp.rom0_off;
            const romx: usize = cartp.romx_off;
            cycles = dynarecmod.dynarecRunBlock(dynp, cpup, busp);
            if (cycles == 0) {
                cycles = cpumod.cpuStep(cpup, busp);
                dynp.stats.fallback +%= 1;
            }
            invalidateChangedBanks(e, rom0, romx);
        } else {
            cycles = interpreterStep(e);
        }
        total += cycles;
        const busp2: *const mmumod.Bus = &e.bus;
        const dot_delta: u32 = if (busp2.double_speed) cycles / 2 else cycles;
        dots += dot_delta;
        ppuSyncIn(e);
        ppumod.ppuTick(&e.ppu, dot_delta, &e.bus);
        ppuSyncOut(e);
    }
    return total;
}

pub fn emuFramebuffer(e: *const Emu) []const u32 {
    return ppumod.ppuFramebuffer(&e.ppu);
}

pub fn emuSetButtons(e: *Emu, bits: u8) void {
    e.buttons = bits;
    e.bus.buttons = bits;
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

pub fn emuAudioSamples(e: *Emu, out: []i16) usize {
    return apumod.apuSamples(&e.bus.apu, out);
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
