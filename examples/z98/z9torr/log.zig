// log.zig — z9torr: minimal, env-gated diagnostic file logger.
//
// Enabled only when `Z9TORR_LOG` is set in the environment. When unset, every
// entry point is a strict no-op (no file is opened, no `std_os` side effect
// beyond the one `env` lookup in `begin`). The path is the env value when it
// looks like a path (contains '/' or '.'); otherwise `z9torr.log` in the CWD.
//
// Z98 rules: free functions only, no generics, strict `@intCast`, no float
// formatting (integers are written by hand into a local buffer).

const std = @import("std");

// Module-global write fd + enabled flag. Concrete initializers are fine for a
// program module (mirrors `tracker.zig`'s `g_failure_len`).
var g_fd: usize = 0;
var g_enabled: bool = false;

// A value "looks like a path" when it carries a directory separator or an
// extension; this keeps the documented `Z9TORR_LOG=1` form on the default path.
fn looksLikePath(v: []const u8) bool {
    var i: usize = 0;
    while (i < v.len) : (i += 1) {
        if (v[i] == '/' or v[i] == '.') return true;
    }
    return false;
}

pub fn begin() void {
    var val: ?[]const u8 = std.os.env("Z9TORR_LOG");
    if (val) |v| {
        var path: []const u8 = "z9torr.log";
        if (looksLikePath(v)) path = v;
        var fd: ?usize = std.io.fileOpen(path, true);
        if (fd) |f| {
            g_fd = f;
            g_enabled = true;
        }
    }
}

pub fn end() void {
    if (g_enabled) {
        std.io.fileClose(g_fd);
        g_enabled = false;
    }
}

pub fn s(m: []const u8) void {
    if (!g_enabled) return;
    std.io.fileWrite(g_fd, m);
}

pub fn nl() void {
    if (!g_enabled) return;
    var b: [1]u8 = undefined;
    b[0] = '\n';
    std.io.fileWrite(g_fd, b[0..1]);
}

// Manual unsigned decimal into a local buffer (no printf/float path).
fn putU64(v: u64) void {
    if (!g_enabled) return;
    var tmp: [20]u8 = undefined;
    var len: usize = 0;
    var x: u64 = v;
    if (x == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (x > 0) : (x = x / 10) {
            tmp[len] = '0' + @intCast(u8, x % 10);
            len += 1;
        }
    }
    var out: [20]u8 = undefined;
    var k: usize = 0;
    while (k < len) : (k += 1) {
        out[k] = tmp[len - 1 - k];
    }
    std.io.fileWrite(g_fd, out[0..len]);
}

pub fn u64v(v: u64) void {
    putU64(v);
}

pub fn u32v(v: u32) void {
    putU64(@intCast(u64, v));
}

pub fn i32v(v: i32) void {
    if (!g_enabled) return;
    if (v < 0) {
        s("-");
        var mag: u32 = @intCast(u32, 0 - @intCast(i64, v));
        putU64(@intCast(u64, mag));
    } else {
        putU64(@intCast(u64, v));
    }
}

// Lowercase-hex writer for the byte-level handshake/tracker diagnostics.
// Processes the input in 32-byte chunks so one 64-byte local buffer covers any
// input (including the 68-byte handshake) with no allocation. Strict no-op when
// disabled.
fn hexNib(v: u8) u8 {
    if (v < 10) return '0' + v;
    return 'a' + (v - 10);
}

pub fn hex(data: []const u8) void {
    if (!g_enabled) return;
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < data.len) {
        var n: usize = data.len - i;
        if (n > 32) n = 32;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            var by: u8 = data[i + k];
            buf[k * 2] = hexNib((by >> 4) & @intCast(u8, 15));
            buf[k * 2 + 1] = hexNib(by & @intCast(u8, 15));
        }
        std.io.fileWrite(g_fd, buf[0 .. n * 2]);
        i += n;
    }
}
