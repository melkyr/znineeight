// stdlib_time_monotonic_avail_xmod — STDLIB std_time (L1) monotonic-source
// availability + counter/frequency pair consistency GREEN fixture.
//
// Operator fix (Plan A Task 3 review): POSIX highRes uses
// clock_gettime(CLOCK_MONOTONIC) when the target defines CLOCK_MONOTONIC
// (compile-time `#if defined(CLOCK_MONOTONIC)` in std_time_prelude.h), else
// gettimeofday; clockMonotonicAvailable() exposes that selection. win32 keeps
// QueryPerformanceCounter, with QPC/QPF treated as one atomic pair, so highRes
// and highResFreq can never disagree.
//
// GREEN (contract): deterministic byte-exact stdout `time monotonic avail ok\n`
// (RUNRC=0).
const std = @import("std");
const time = @import("std_time.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    var avail = time.clockMonotonicAvailable();
    var freq = time.highResFreq();
    ck(freq > @intCast(u64, 0), "freq positive");

    if (@isWindows()) {
        // win32 uses the QPC/QPF pair, so the CLOCK_MONOTONIC probe is false.
        // A usable pair reports QPF (> 0); the atomic fallback reports 1e6.
        ck(!avail, "win32 uses QPC, not CLOCK_MONOTONIC");
    } else {
        // Host toolchain (32-bit glibc) defines CLOCK_MONOTONIC: the compile-time
        // selection must have picked the monotonic nanosecond source.
        ck(avail, "POSIX monotonic source selected");
        ck(freq == @intCast(u64, 1000000000), "monotonic freq == 1e9");
    }

    // Pair consistency: the highRes delta scaled by highResFreq must match the
    // wall time of a 20ms sleep. A desynced counter/frequency pair (e.g. QPC
    // counts reported against the 1e6 fallback) would blow the upper bound.
    var t0: u64 = time.highRes();
    time.sleepMs(@intCast(u32, 20));
    var t1: u64 = time.highRes();
    var ms: u64 = (t1 - t0) * @intCast(u64, 1000) / freq;
    ck(ms >= @intCast(u64, 10), "pair delta >= 10ms");
    ck(ms <= @intCast(u64, 2000), "pair delta <= 2s");

    // The monotonic source is non-decreasing over 100 calls.
    var prev: u64 = time.highRes();
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var now: u64 = time.highRes();
        ck(now >= prev, "highRes non-decreasing");
        prev = now;
    }

    if (g_fail == 0) {
        std.io.write("time monotonic avail ok\n");
    } else {
        std.io.write("time monotonic avail FAIL\n");
    }
}
