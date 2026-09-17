/* std_os_prelude.h — target-neutral OS include prelude for std_os extern calls
   (Plan A Task 2; the net_prelude.h analog). Whichever C toolchain compiles the
   dump (gcc -m32 / i686-w64-mingw32-gcc) selects the branch, so the only
   prototype source for every std_os extern is the matching OS header. The
   compiler PAL (zig_pal.c) is untouched; std_os's OS specifics live in the
   std-side std_os_pal.zig (R8: the compiler's cost is what it imports, the
   library's cost is what emits). */
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>   /* GetCurrentDirectoryA */
#else
#include <unistd.h>    /* getcwd */
#endif
#include <stdlib.h>        /* getenv, exit */
