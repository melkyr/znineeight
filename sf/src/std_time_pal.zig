// std_time_pal.zig — Z98 std_time std-side PAL: target-selected extern "c" OS
// bindings (the std_net.zig pattern, R8). The compiler PAL (pal.zig /
// zig_pal.c) is NOT touched: the compiler's cost is what it imports, the
// library's cost is what emits.
//
// std_time_prelude.h (the net_prelude.h / std_os_prelude.h analog, found on the
// compiler include path and emitted next to the program) supplies the per-OS C
// prototypes, because the C89 emitter emits no prototype for non-variadic
// externs. The externs are declared here; the @isWindows() guards live in
// std_time.zig, which also @cIncludes the prelude so the prototypes are visible
// at its call sites.

@cInclude("<std_time_prelude.h>");

// POSIX gettimeofday's struct timeval (32-bit: { time_t sec, suseconds_t usec }
// = { i32, i32 }; byte-exact vs <sys/time.h>, the same S2-I layout probe as
// std_net's TimeVal).
pub const TimeVal = struct {
    tv_sec: i32,
    tv_usec: i32,
};

// win32 (kernel32, always present on win9x): milliseconds since boot; wraps
// every ~49.7 days.
pub extern "stdcall" fn GetTickCount() u32;

// win32: high-resolution performance counter + its frequency (counts/second).
// Both return non-zero on success; zero when no hardware counter exists (the
// documented ticksMs*1000 fallback).
pub extern "stdcall" fn QueryPerformanceCounter(lpPerformanceCount: *i64) i32;
pub extern "stdcall" fn QueryPerformanceFrequency(lpFrequency: *i64) i32;

// POSIX: fill tv with the wall-clock time since the epoch; returns 0 on
// success, -1 on failure. tv is *void (the caller's TimeVal blob is byte-exact
// vs the native struct timeval at offset 0, so a pointer cast lowers cleanly
// without a type-mismatch warning — the same S2-I layout probe std_net uses);
// tz is obsolete and passed null.
pub extern "c" fn gettimeofday(tv: *void, tz: *void) i32;

// Portable CRT: UTC seconds since the epoch; t is obsolete and passed null.
pub extern "c" fn time(t: *void) i64;
