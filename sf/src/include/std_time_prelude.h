/* std_time_prelude.h — target-neutral time include prelude for std_time extern
   calls (Plan A Task 3; the net_prelude.h / std_os_prelude.h analog). Whichever
   C toolchain compiles the dump (gcc -m32 / i686-w64-mingw32-gcc) selects the
   branch, so the only prototype source for every std_time extern is the matching
   OS header. The compiler PAL (zig_pal.c) is untouched; std_time's OS specifics
   live in the std-side std_time_pal.zig (R8: the compiler's cost is what it
   imports, the library's cost is what emits). */
#ifndef STD_TIME_PRELUDE_H
#define STD_TIME_PRELUDE_H
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>   /* GetTickCount, QueryPerformanceCounter/Frequency */
#else
/* clock_gettime/CLOCK_MONOTONIC are POSIX.1b; -std=c89 defines __STRICT_ANSI__
   and hides them unless a feature-test macro is requested BEFORE <time.h>. This
   prelude is the first libc header in a std_time TU, so the request is
   effective. _DEFAULT_SOURCE keeps the BSD usleep (the @sleepMs builtin) and
   gettimeofday declared. */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 199309L
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE 1
#endif
#include <sys/time.h>  /* gettimeofday */
#endif
#include <time.h>          /* time; POSIX: clock_gettime, struct timespec */

/* Compile-time monotonic-availability probe (operator fix, Plan A Task 3
   review): win32 has no CLOCK_MONOTONIC and uses QueryPerformanceCounter
   instead, so the probe is false there. */
#if defined(_WIN32)
#define Z98_HAS_CLOCK_MONOTONIC 0
#elif defined(CLOCK_MONOTONIC)
#define Z98_HAS_CLOCK_MONOTONIC 1
#else
#define Z98_HAS_CLOCK_MONOTONIC 0
#endif

/* A function-like macro, so the emitted call folds to the integer constant at C
   compile time (this is the compile-time check, not a runtime probe). */
#define z98_time_clock_monotonic_available() Z98_HAS_CLOCK_MONOTONIC

/* Monotonic nanoseconds, compile-time selected. POSIX only — win32 uses
   QueryPerformanceCounter and never calls this. static __inline__ (not C89
   `inline`) keeps an including TU that does not call it warning-free. */
#ifndef _WIN32
static __inline__ long long z98_time_monotonic_ns(void) {
#if Z98_HAS_CLOCK_MONOTONIC
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
#else
    struct timeval tv;
    gettimeofday(&tv, 0);
    return (long long)tv.tv_sec * 1000000LL + (long long)tv.tv_usec;
#endif
}
#endif
#endif /* STD_TIME_PRELUDE_H */
