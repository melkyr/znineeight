// stdlib_os_cwd_xmod — STDLIB std_os (L1) cwd non-empty GREEN fixture.
//
// Contract (blueprint §3 L1): cwd(arena) ![]u8 allocates ONCE per call from the
// arena and fills via GetCurrentDirectoryA (win32) / getcwd (linux), whose
// prototypes come from the authorized std_os_prelude.h. The returned slice is
// the actual path (NUL excluded). Errors: OutOfMemory (arena) or CwdFailed.
//
// The path itself is machine-dependent, so the fixture asserts only structural
// properties (non-empty, no leading NUL, stable across a second call) and
// prints a fixed line — R6 determinism.
//
// GREEN (contract): deterministic byte-exact stdout `os cwd ok\n` (RUNRC=0).
const std = @import("std");
const os = @import("std_os.zig");

var g_buf: [16384]u8 = undefined;
var g_arena = std.arena.init(g_buf[0..]);

var g_fallback_storage: [1]u8 = undefined;
var g_fallback: []u8 = g_fallback_storage[0..0];

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    var d = os.cwd(&g_arena) catch g_fallback;
    ck(d.len > 0, "cwd non-empty");
    ck(d[0] != 0, "cwd no leading NUL");

    // alloc-once per call: a second call draws a fresh arena allocation and
    // yields the same machine path (same length).
    var d2 = os.cwd(&g_arena) catch g_fallback;
    ck(d2.len == d.len, "cwd stable across calls");
    ck(d2.len > 0, "second cwd non-empty");

    // std.zig re-export smoke check.
    var d3 = std.os.cwd(&g_arena) catch g_fallback;
    ck(d3.len == d.len, "std.os re-export");

    if (g_fail == 0) {
        std.io.write("os cwd ok\n");
    } else {
        std.io.write("os cwd FAIL\n");
    }
}
