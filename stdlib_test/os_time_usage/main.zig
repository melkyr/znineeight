// stdlib_test/os_time_usage — Plan A Task 7 (R7b) usage program.
//
// Composes std_os (L1) + std_time (L1) + std_debug (L1) into one intended
// workflow: capture argc/argv with initArgs, read the working directory with
// cwd, sample the monotonic and tick clocks, and route every result through
// std_debug (log / logInt / passing assert).
//
// Determinism (R6): the cwd path, argv(0), and the clock samples are all
// machine/time-dependent, so NONE is printed raw. Each module is exercised
// against its documented contract (std_os: non-empty cwd + argv aliasing;
// std_time: non-decreasing highRes/ticksMs, positive freq, wall clock in the
// documented 2020..2100 window) and only the boolean outcome is emitted.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0) when invoked
// with no arguments (argc == 1):
//   os_time_usage
//   argc: 1
//   cwd: 1
//   mono: 1
//   tick: 1
//   os_time ok
// A mismatch increments g_fail and calls @panic; the final line is
// `os_time ok` only when g_fail == 0.
const std = @import("std");
const os = @import("std_os.zig");
const time = @import("std_time.zig");

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

pub fn main(argc: i32, argv: [*]*const u8) void {
    // --- std_os: capture the process identity ------------------------------
    os.initArgs(argc, argv);
    ck(os.argc() == @intCast(usize, argc), "argc round-trip");
    ck(os.argc() >= 1, "argc >= 1");

    var a0 = os.argv(0);
    ck(a0.len > 0, "argv(0) non-empty");
    ck(a0[a0.len - 1] != 0, "argv(0) excludes NUL");

    // std.zig re-export smoke check.
    ck(std.os.argc() == os.argc(), "std.os re-export");

    var cwd = os.cwd(&g_arena) catch g_fallback;
    ck(cwd.len > 0, "cwd non-empty");
    ck(cwd[0] != 0, "cwd no leading NUL");

    // --- std_time: sample the monotonic + tick clocks ----------------------
    // highRes is non-decreasing over 50 calls (robust to the documented
    // ticksMs*1000 fallback, where consecutive samples are equal).
    var prev: u64 = time.highRes();
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        var now: u64 = time.highRes();
        ck(now >= prev, "highRes non-decreasing");
        prev = now;
    }

    ck(time.highResFreq() > @intCast(u64, 0), "highResFreq positive");

    // Wall clock in the documented 2020-09-13 .. 2100 window.
    var w: i64 = time.wallClockUnix();
    ck(w > @intCast(i64, 1600000000), "wallClockUnix after 2020");
    ck(w < @intCast(i64, 4102444800), "wallClockUnix before 2100");

    // ticksMs is non-decreasing across a short sleep.
    var t0: u32 = time.ticksMs();
    time.sleepMs(@intCast(u32, 5));
    var t1: u32 = time.ticksMs();
    ck(t1 >= t0, "ticksMs non-decreasing");

    // --- std_debug: route diagnostics --------------------------------------
    std.debug.log("os_time_usage\n");
    std.debug.assert(g_fail == 0);
    std.debug.logInt("argc", @intCast(i32, os.argc()));
    std.debug.logInt("cwd", 1);
    std.debug.logInt("mono", 1);
    std.debug.logInt("tick", 1);

    if (g_fail == 0) {
        std.debug.log("os_time ok\n");
    } else {
        std.debug.log("os_time FAIL\n");
    }
}
