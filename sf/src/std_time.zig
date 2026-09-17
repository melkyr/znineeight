// std_time.zig — Z98 std lib L1: monotonic and wall-clock time.
//
// Contract (blueprint §3 L1): alloc no | errors no | coroutine no.
// OS specifics live in the std-side PAL std_time_pal.zig (R8); the compiler PAL
// (pal.zig / zig_pal.c) is never touched. Per-OS C prototypes come from the
// authorized std_time_prelude.h (the net_prelude.h analog).
//
// ticksMs wraps (win32 GetTickCount; ~49.7 days). highRes is the monotonic
// counter whose unit is 1/highResFreq() seconds: win32
// QueryPerformanceCounter, POSIX clock_gettime(CLOCK_MONOTONIC) when the
// target defines it, else gettimeofday (operator fix, Plan A Task 3 review).
// clockMonotonicAvailable() exposes the POSIX compile-time selection. On
// hardware without a high-res timer highRes falls back to ticksMs() * 1000
// (R6, documented and deterministic — consecutive samples are then equal,
// which the monotonicity fixture allows).

const pal = @import("std_time_pal.zig");

@cInclude("<std_time_prelude.h>");

// The null `void*` that gettimeofday's obsolete tz and time's obsolete t must
// receive (Z98 `null` is optional-only; same construction std_net uses).
fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

// win32: query the QueryPerformanceCounter/Frequency pair atomically. Returns 0
// when either query fails or the frequency is zero; otherwise stores the counter
// and frequency into the out params and returns 1. A single guard governs both,
// so highRes and highResFreq can never disagree about whether the counter is
// usable (the Plan A Task 3 review fix: previously highRes gated on QPC alone
// and highResFreq on QPF alone, so a 0 QPF could report the 1e6 fallback while
// highRes returned raw QPC counts). The @isWindows() guard keeps the QPC calls
// out of the emitted linux C (the function is emitted regardless of its
// comptime-dead call sites).
fn winQpcPair(counter: *i64, freq: *i64) u32 {
    if (@isWindows()) {
        var c: i64 = undefined;
        var f: i64 = undefined;
        const ok_c = pal.QueryPerformanceCounter(&c);
        if (ok_c == 0) return 0;
        const ok_f = pal.QueryPerformanceFrequency(&f);
        if (ok_f == 0) return 0;
        if (f == 0) return 0;
        counter.* = c;
        freq.* = f;
        return 1;
    } else {
        return 0;
    }
}

// Milliseconds since boot on win32; on POSIX, wall-clock milliseconds since the
// epoch truncated to 32 bits (wraps every ~49.7 days, matching GetTickCount's
// wrapping contract).
pub fn ticksMs() u32 {
    if (@isWindows()) {
        return pal.GetTickCount();
    } else {
        var tv: pal.TimeVal = undefined;
        _ = pal.gettimeofday(@ptrCast(*void, &tv), nullVoid());
        var secs: u64 = @intCast(u64, tv.tv_sec);
        var usecs: u64 = @intCast(u64, tv.tv_usec);
        var ms: u64 = secs * @intCast(u64, 1000) + usecs / @intCast(u64, 1000);
        return @intCast(u32, ms & @intCast(u64, 0xFFFFFFFF));
    }
}

// High-resolution monotonic counter. win32: the atomic QPC/QPF pair (falling
// back to ticksMs() * 1000 when unusable); POSIX: the prelude's compile-time
// selected monotonic read (clock_gettime(CLOCK_MONOTONIC) or gettimeofday).
pub fn highRes() u64 {
    if (@isWindows()) {
        var c: i64 = undefined;
        var f: i64 = undefined;
        if (winQpcPair(&c, &f) == 0) {
            return @intCast(u64, ticksMs()) * @intCast(u64, 1000);
        }
        return @intCast(u64, c);
    } else {
        return @intCast(u64, pal.z98_time_monotonic_ns());
    }
}

// True when the POSIX target provides clock_gettime(CLOCK_MONOTONIC), selected
// at C compile time by `#if defined(CLOCK_MONOTONIC)` in std_time_prelude.h
// (the probe is a function-like macro, so the emitted call folds to a
// constant). Always false on win32, which uses QueryPerformanceCounter.
pub fn clockMonotonicAvailable() bool {
    if (@isWindows()) {
        return false;
    } else {
        return pal.z98_time_clock_monotonic_available() != 0;
    }
}

// Counter ticks per second. win32: the atomic QPC/QPF pair (1e6 fallback when
// unusable, matching the ticksMs() * 1000 unit); POSIX: 1e9 for the monotonic
// nanosecond source, 1e6 for the gettimeofday microsecond fallback.
pub fn highResFreq() u64 {
    if (@isWindows()) {
        var c: i64 = undefined;
        var f: i64 = undefined;
        if (winQpcPair(&c, &f) == 0) return @intCast(u64, 1000000);
        return @intCast(u64, f);
    } else {
        if (clockMonotonicAvailable()) {
            return @intCast(u64, 1000000000);
        } else {
            return @intCast(u64, 1000000);
        }
    }
}

// UTC seconds since the epoch.
pub fn wallClockUnix() i64 {
    return pal.time(nullVoid());
}

// Sleep for ms milliseconds; wraps the @sleepMs builtin directly (no std_io
// import; R3).
pub fn sleepMs(ms: u32) void {
    @sleepMs(ms);
}
