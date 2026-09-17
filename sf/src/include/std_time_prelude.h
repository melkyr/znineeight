/* std_time_prelude.h — target-neutral time include prelude for std_time extern
   calls (Plan A Task 3; the net_prelude.h / std_os_prelude.h analog). Whichever
   C toolchain compiles the dump (gcc -m32 / i686-w64-mingw32-gcc) selects the
   branch, so the only prototype source for every std_time extern is the matching
   OS header. The compiler PAL (zig_pal.c) is untouched; std_time's OS specifics
   live in the std-side std_time_pal.zig (R8: the compiler's cost is what it
   imports, the library's cost is what emits). */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>   /* GetTickCount, QueryPerformanceCounter/Frequency */
#else
#include <sys/time.h>  /* gettimeofday */
#endif
#include <time.h>          /* time */
