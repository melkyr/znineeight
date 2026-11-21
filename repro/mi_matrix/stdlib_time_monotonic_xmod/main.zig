// stdlib_time_monotonic_xmod — STDLIB std_time (L1) monotonicity GREEN fixture.
//
// Contract (blueprint §3 L1): std_time is alloc-free (no arena), error-free,
// and non-coroutine. ticksMs() is a wrapping u32 millisecond tick; highRes() is
// a u64 high-resolution counter whose unit is 1/highResFreq() seconds;
// wallClockUnix() is UTC seconds. R6: highRes falls back to ticksMs() * 1000 on
// hardware without a high-res timer, so the monotonicity check uses
// non-decreasing (>=), not strictly increasing — the fallback yields equal
// consecutive samples.
//
// GREEN (contract): deterministic byte-exact stdout `time monotonic ok\n`
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
    // highRes is non-decreasing over 100 calls (robust to the ticksMs*1000
    // fallback, where consecutive samples are equal).
    var prev: u64 = time.highRes();
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var now: u64 = time.highRes();
        ck(now >= prev, "highRes non-decreasing");
        prev = now;
    }

    // ticksMs is non-decreasing over 100 calls (no wrap in a microsecond-scale
    // window; the ~49.7-day wrap is documented and out of fixture scope).
    var pt: u32 = time.ticksMs();
    i = 0;
    while (i < 100) : (i += 1) {
        var nt: u32 = time.ticksMs();
        ck(nt >= pt, "ticksMs non-decreasing");
        pt = nt;
    }

    // Frequency is a positive divisor (never zero).
    ck(time.highResFreq() > @intCast(u64, 0), "highResFreq positive");

    // Wall clock is after 2020-09-13 (1_600_000_000 UTC) and before 2100.
    var w: i64 = time.wallClockUnix();
    ck(w > @intCast(i64, 1600000000), "wallClockUnix after 2020");
    ck(w < @intCast(i64, 4102444800), "wallClockUnix before 2100");

    // std.zig re-export smoke check.
    ck(std.time.highResFreq() == time.highResFreq(), "std.time re-export");

    if (g_fail == 0) {
        std.io.write("time monotonic ok\n");
    } else {
        std.io.write("time monotonic FAIL\n");
    }
}
