// emu.zig — z9gb Emu facade (P1: fixed storage + deterministic framebuffer).
//
// Pure Z98 free functions only. The 8 MiB ROM buffer lives inside `Emu`; the
// single instance must be a module-scope `var` (never a stack local and never a
// by-value copy) so the 1 MiB stack is never touched. No heap allocation.

const std = @import("std");
const filemod = @import("std_file");

const ROM_CAP: usize = 8 * 1024 * 1024;
const SERIAL_CAP: usize = 4096;
const SAVE_CAP: usize = 260;
const FRAME_W: usize = 160;
const FRAME_H: usize = 144;

pub const EmuConfig = struct { cgb: bool, serial_log: bool, turbo: bool, dynarec: bool };

pub const EmuError = error{ RomTooLarge, BadHeader, UnsupportedMbc, CgbRequired, SaveCorrupt, Io, OutOfMemory };

pub const Emu = struct {
    rom: [ROM_CAP]u8,
    rom_len: usize,
    fb: [FRAME_W * FRAME_H]u32,
    serial_log: [SERIAL_CAP]u8,
    serial_len: usize,
    buttons: u8,
    cfg: EmuConfig,
    save_path: [SAVE_CAP]u8,
    save_len: usize,
};

pub fn emuInit(e: *Emu, cfg: EmuConfig) void {
    // Scalar fields only: a whole-`Emu` literal would materialize an ~8.5 MiB
    // temporary on the 1 MiB stack. `rom`, `fb`, `serial_log`, and `save_path`
    // are fixed storage written by their owners.
    e.rom_len = 0;
    e.serial_len = 0;
    e.buttons = 0;
    e.cfg = cfg;
    e.save_len = 0;
}

// P1 loader contract: a size-checked copy into the fixed 8 MiB buffer, no header
// parsing (that is P2's). Header-side errors remain in the shared error set.
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
}

pub fn emuReset(e: *Emu) void {
    e.serial_len = 0;
    e.buttons = 0;
}

pub fn emuSelfTestPattern(e: *Emu) void {
    var y: usize = 0;
    while (y < FRAME_H) : (y += 1) {
        var x: usize = 0;
        while (x < FRAME_W) : (x += 1) {
            e.fb[y * FRAME_W + x] = 0x00010000 | @intCast(u32, x & 0xFF) | (@intCast(u32, y & 0xFF) << 8);
        }
    }
}

pub fn emuRunFrame(e: *Emu) u32 {
    emuSelfTestPattern(e);
    return 70224;
}

pub fn emuFramebuffer(e: *const Emu) []const u32 {
    return e.fb[0..];
}

pub fn emuSetButtons(e: *Emu, bits: u8) void {
    e.buttons = bits;
}

pub fn emuTakeSerial(e: *Emu, out: []u8) usize {
    var n: usize = e.serial_len;
    if (n > out.len) n = out.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = e.serial_log[i];
    }
    if (n < e.serial_len) {
        var j: usize = 0;
        while (j < e.serial_len - n) : (j += 1) {
            e.serial_log[j] = e.serial_log[n + j];
        }
    }
    e.serial_len -= n;
    return n;
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

// P1 has no save backend (P2 Task 8 fills these in without API churn).
pub fn emuSaveBattery(e: *Emu) EmuError!void {
    _ = e;
    return error.Io;
}

pub fn emuLoadBattery(e: *Emu) EmuError!void {
    _ = e;
    return error.Io;
}
