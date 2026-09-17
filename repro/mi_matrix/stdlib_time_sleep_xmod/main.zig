// stdlib_time_sleep_xmod — STDLIB std_time (L1) sleep-with-tolerance fixture.
//
// Contract (blueprint §3 L1): sleepMs(ms) wraps the @sleepMs builtin directly
// (no std_io import; R3). Tolerance: the measured highRes delta must cover the
// requested interval minus scheduling slack, and must not be absurdly long.
// The documented fallback highRes = ticksMs()*1000 is handled by scaling the
// delta through highResFreq().
//
// GREEN (contract): deterministic byte-exact stdout `time sleep ok\n` (RUNRC=0).
const std = @import("std");
const time = @import("std_time.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

// Convert a highRes counter delta to whole milliseconds via the frequency.
fn elapsedMs(t0: u64, t1: u64, freq: u64) u64 {
    return (t1 - t0) * @intCast(u64, 1000) / freq;
}

pub fn main() void {
    // sleepMs(0) returns promptly and never moves time backwards.
    var z0: u64 = time.highRes();
    time.sleepMs(@intCast(u32, 0));
    var z1: u64 = time.highRes();
    ck(z1 >= z0, "sleepMs(0) non-negative");

    // sleepMs(50): at least ~40ms (slack), at most 5s (loaded-machine guard).
    var freq: u64 = time.highResFreq();
    ck(freq > @intCast(u64, 0), "freq positive");
    var t0: u64 = time.highRes();
    time.sleepMs(@intCast(u32, 50));
    var t1: u64 = time.highRes();
    var ms: u64 = elapsedMs(t0, t1, freq);
    ck(ms >= @intCast(u64, 40), "slept at least 40ms");
    ck(ms <= @intCast(u64, 5000), "slept at most 5s");

    if (g_fail == 0) {
        std.io.write("time sleep ok\n");
    } else {
        std.io.write("time sleep FAIL\n");
    }
}
