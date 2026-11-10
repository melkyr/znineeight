// main.zig — z9gb entry point (P1: deterministic headless framebuffer).
//
// Pure Z98 CLI:
//   --headless            select the headless platform (the only P1 backend)
//   --frames <n>          run n frames (default 1)
//   --fb-out <path>       write 160*144 little-endian u32 pixels
//   --rom <path>          size-checked copy into the fixed 8 MiB ROM buffer
//
// The single `Emu` lives at module scope: its fixed ROM buffer is 8 MiB, so it
// is never a stack local or a by-value copy (the 1 MiB stack is a hard limit).

const std = @import("std");
const filemod = @import("std_file");
const emu = @import("emu.zig");
const headless = @import("platform/headless.zig");

const FRAME_W: u32 = 160;
const FRAME_H: u32 = 144;
const FB_PIXELS: usize = 160 * 144;
const FB_BYTES: usize = FB_PIXELS * 4;

const VERDICT_NONE: u8 = 0;
const VERDICT_PASS: u8 = 1;
const VERDICT_FAIL: u8 = 2;

var g_emu: emu.Emu = undefined;
var g_fb_bytes: [FB_BYTES]u8;
var g_line_buf: [96]u8;
var g_line_len: usize = 0;
var g_verdict: u8 = VERDICT_NONE;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a) |item, i| {
        if (item != b[i]) return false;
    }
    return true;
}

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        var c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > 1000000000) return null;
    }
    return @intCast(u32, v);
}

fn trimEq(buf: []const u8, len: usize, want: []const u8) bool {
    var s: usize = 0;
    var e: usize = len;
    while (s < e and (buf[s] == ' ' or buf[s] == '\t')) s += 1;
    while (e > s and (buf[e - 1] == ' ' or buf[e - 1] == '\t')) e -= 1;
    if (e - s != want.len) return false;
    var i: usize = 0;
    while (i < want.len) : (i += 1) {
        if (buf[s + i] != want[i]) return false;
    }
    return true;
}

// Blargg verdicts are whole serial lines. Track the current line and latch the
// terminal `Passed`/`Passed all tests`/`Failed` so main can exit before the
// frame cap. Both the period and no-period spellings are accepted.
fn finishSerialLine() void {
    if (trimEq(g_line_buf[0..], g_line_len, "Passed") or
        trimEq(g_line_buf[0..], g_line_len, "Passed all tests.") or
        trimEq(g_line_buf[0..], g_line_len, "Passed all tests"))
    {
        g_verdict = VERDICT_PASS;
    } else if (trimEq(g_line_buf[0..], g_line_len, "Failed")) {
        g_verdict = VERDICT_FAIL;
    }
    g_line_len = 0;
}

fn feedSerial(data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        const c: u8 = data[i];
        if (c == '\n' or c == '\r') {
            finishSerialLine();
        } else if (g_line_len < g_line_buf.len) {
            g_line_buf[g_line_len] = c;
            g_line_len += 1;
        }
    }
}

fn drainSerial() void {
    var buf: [512]u8 = undefined;
    while (true) {
        const got: usize = emu.emuTakeSerial(&g_emu, buf[0..]);
        if (got == 0) break;
        std.io.write(buf[0..got]);
        feedSerial(buf[0..got]);
    }
}

fn reportMooneye() void {
    if (!emu.emuMooneyeStopped(&g_emu)) {
        var m: []const u8 = "mooneye: TIMEOUT (no breakpoint)\n";
        std.io.write(m);
        return;
    }
    var sig: [6]u8 = undefined;
    emu.emuMooneyeSignature(&g_emu, sig[0..]);
    std.io.write("mooneye: ");
    if (emu.emuMooneyePass(&g_emu)) {
        std.io.write("PASS");
    } else {
        std.io.write("FAIL");
    }
    std.io.write(" B=");
    std.io.printInt(@intCast(i32, sig[0]));
    std.io.write(" C=");
    std.io.printInt(@intCast(i32, sig[1]));
    std.io.write(" D=");
    std.io.printInt(@intCast(i32, sig[2]));
    std.io.write(" E=");
    std.io.printInt(@intCast(i32, sig[3]));
    std.io.write(" H=");
    std.io.printInt(@intCast(i32, sig[4]));
    std.io.write(" L=");
    std.io.printInt(@intCast(i32, sig[5]));
    std.io.write("\n");
}

// Unix epochs can exceed parseU32's frame-count cap.
fn parseI64(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    var neg: bool = false;
    var i: usize = 0;
    if (s[0] == '-') {
        neg = true;
        i = 1;
        if (s.len == 1) return null;
    }
    var v: i64 = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        const d: i64 = @intCast(i64, c - '0');
        if (v > 922337203685477580 or (v == 922337203685477580 and d > 7)) return null;
        v = v * 10 + d;
    }
    if (neg) return -v;
    return v;
}

// Little-endian writers: the goldens are canonical LE regardless of host.
fn putLe32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @intCast(u8, v & 0xff);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xff);
    buf[off + 2] = @intCast(u8, (v >> 16) & 0xff);
    buf[off + 3] = @intCast(u8, (v >> 24) & 0xff);
}

fn writeFramebuffer(path: []const u8) bool {
    const fb: []const u32 = emu.emuFramebuffer(&g_emu);
    var i: usize = 0;
    while (i < fb.len) : (i += 1) {
        putLe32(g_fb_bytes[0..], i * 4, fb[i]);
    }
    filemod.writeAll(path, g_fb_bytes[0..FB_BYTES]) catch return false;
    return true;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    var frames: u32 = 1;
    var fb_out: []const u8 = "";
    var rom_path: []const u8 = "";
    var serial: bool = false;
    var turbo: bool = false;
    var mooneye: bool = false;
    var save: bool = false;
    var rtc_fixed: i64 = 0;
    var have_rtc_fixed: bool = false;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--headless")) {
            // Headless is the only P1 backend; nothing to switch.
        } else if (eq(tok, "--frames")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            if (parseU32(argAt(argv, i))) |v| {
                frames = v;
            } else {
                std.os.exit(1);
            }
        } else if (eq(tok, "--fb-out")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            fb_out = argAt(argv, i);
        } else if (eq(tok, "--rom")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            rom_path = argAt(argv, i);
        } else if (eq(tok, "--serial")) {
            serial = true;
        } else if (eq(tok, "--turbo")) {
            turbo = true;
        } else if (eq(tok, "--mooneye")) {
            mooneye = true;
        } else if (eq(tok, "--save")) {
            save = true;
        } else if (eq(tok, "--rtc-fixed")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            if (parseI64(argAt(argv, i))) |v| {
                rtc_fixed = v;
                have_rtc_fixed = true;
            } else {
                std.os.exit(1);
            }
        } else {
            std.os.exit(1);
        }
    }

    emu.emuInit(&g_emu, emu.EmuConfig{ .cgb = false, .serial_log = serial, .turbo = turbo, .dynarec = false });
    if (have_rtc_fixed) emu.emuSetRtcFixed(&g_emu, rtc_fixed);

    if (rom_path.len != 0) {
        emu.emuLoadRom(&g_emu, rom_path) catch |e| {
            if (e == error.RomTooLarge) {
                var m: []const u8 = "z9gb: ROM too large (max 8 MiB)\n";
                std.io.write(m);
            } else {
                var m: []const u8 = "z9gb: cannot read ROM\n";
                std.io.write(m);
            }
            std.os.exit(2);
        };
        emu.emuReset(&g_emu);
    }
    emu.emuSetMooneye(&g_emu, mooneye);

    var plat = headless.platformHeadless();
    if (!plat.open_fn(plat.state, FRAME_W, FRAME_H, 1)) {
        var m: []const u8 = "z9gb: cannot open headless platform\n";
        std.io.write(m);
        std.os.exit(2);
    }

    var f: u32 = 0;
    while (f < frames) : (f += 1) {
        _ = emu.emuRunFrame(&g_emu);
        if (serial) drainSerial();
        if (mooneye and emu.emuMooneyeStopped(&g_emu)) break;
        if (serial and g_verdict != VERDICT_NONE) break;
    }
    if (serial) {
        drainSerial();
        finishSerialLine();
    }
    plat.present_fn(plat.state, emu.emuFramebuffer(&g_emu));

    if (mooneye) reportMooneye();

    if (fb_out.len != 0) {
        if (!writeFramebuffer(fb_out)) {
            var m: []const u8 = "z9gb: cannot write framebuffer\n";
            std.io.write(m);
            plat.close_fn(plat.state);
            std.os.exit(2);
        }
    }

    if (save) {
        emu.emuSaveBattery(&g_emu) catch {
            var m: []const u8 = "z9gb: cannot write save\n";
            std.io.write(m);
            plat.close_fn(plat.state);
            std.os.exit(2);
        };
    }

    plat.close_fn(plat.state);
    std.os.exit(0);
}
