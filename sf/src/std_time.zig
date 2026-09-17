// std_time.zig — Z98 std lib L1: monotonic and wall-clock time.
//
// Contract (blueprint §3 L1): alloc no | errors no | coroutine no.
// OS specifics live in the std-side PAL std_time_pal.zig (R8); the compiler PAL
// (pal.zig / zig_pal.c) is never touched. Per-OS C prototypes come from the
// authorized std_time_prelude.h (the net_prelude.h analog).
//
// ticksMs wraps (win32 GetTickCount; ~49.7 days). highRes is the
// high-resolution counter (win32 QueryPerformanceCounter, POSIX gettimeofday)
// whose unit is 1/highResFreq() seconds; on hardware without a high-res timer
// it falls back to ticksMs() * 1000 (R6, documented and deterministic —
// consecutive samples are then equal, which the monotonicity fixture allows).

const pal = @import("std_time_pal.zig");

@cInclude("<std_time_prelude.h>");

// The null `void*` that gettimeofday's obsolete tz and time's obsolete t must
// receive (Z98 `null` is optional-only; same construction std_net uses).
fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
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

// High-resolution counter. win32: QueryPerformanceCounter; POSIX: gettimeofday
// microseconds. Falls back to ticksMs() * 1000 when the win32 counter is
// unavailable (QueryPerformanceCounter returns 0).
pub fn highRes() u64 {
    if (@isWindows()) {
        var c: i64 = undefined;
        const ok = pal.QueryPerformanceCounter(&c);
        if (ok == 0) {
            return @intCast(u64, ticksMs()) * @intCast(u64, 1000);
        }
        return @intCast(u64, c);
    } else {
        var tv: pal.TimeVal = undefined;
        _ = pal.gettimeofday(@ptrCast(*void, &tv), nullVoid());
        var secs: u64 = @intCast(u64, tv.tv_sec);
        var usecs: u64 = @intCast(u64, tv.tv_usec);
        return secs * @intCast(u64, 1000000) + usecs;
    }
}

// Counter ticks per second. win32: QueryPerformanceFrequency (falling back to
// 1e6, the POSIX unit, when the counter is unavailable); POSIX: 1e6.
pub fn highResFreq() u64 {
    if (@isWindows()) {
        var f: i64 = undefined;
        const ok = pal.QueryPerformanceFrequency(&f);
        if (ok == 0) return @intCast(u64, 1000000);
        return @intCast(u64, f);
    } else {
        return @intCast(u64, 1000000);
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
