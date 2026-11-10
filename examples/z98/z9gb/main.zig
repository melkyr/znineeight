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

var g_emu: emu.Emu = undefined;
var g_fb_bytes: [FB_BYTES]u8;

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
        } else {
            std.os.exit(1);
        }
    }

    emu.emuInit(&g_emu, emu.EmuConfig{ .cgb = false, .serial_log = false, .turbo = false, .dynarec = false });

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
    }

    var plat = headless.platformHeadless();
    if (!plat.open_fn(plat.state, FRAME_W, FRAME_H, 1)) {
        var m: []const u8 = "z9gb: cannot open headless platform\n";
        std.io.write(m);
        std.os.exit(2);
    }

    var f: u32 = 0;
    while (f < frames) : (f += 1) {
        _ = emu.emuRunFrame(&g_emu);
    }
    plat.present_fn(plat.state, emu.emuFramebuffer(&g_emu));

    if (fb_out.len != 0) {
        if (!writeFramebuffer(fb_out)) {
            var m: []const u8 = "z9gb: cannot write framebuffer\n";
            std.io.write(m);
            plat.close_fn(plat.state);
            std.os.exit(2);
        }
    }

    plat.close_fn(plat.state);
    std.os.exit(0);
}
