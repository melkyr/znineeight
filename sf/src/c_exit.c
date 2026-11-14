#include <stdlib.h>
#if defined(_WIN32) && defined(ZIG_NO_CRT)
#include <windows.h>
#define ZIG_ATEXIT_MAX 32
typedef void (*zig_atexit_fn)(void);
static zig_atexit_fn g_atexit_fns[ZIG_ATEXIT_MAX];
static int g_atexit_count = 0;
static int g_exiting = 0;

int atexit(void (*func)(void)) {
    if (!func || g_exiting || g_atexit_count >= ZIG_ATEXIT_MAX) return -1;
    g_atexit_fns[g_atexit_count++] = func;
    return 0;
}

void exit(int code) {
    if (!g_exiting) {
        g_exiting = 1;
        while (g_atexit_count > 0) {
            zig_atexit_fn fn = g_atexit_fns[--g_atexit_count];
            fn();
        }
    }
    ExitProcess((UINT)code);
}
#endif
void c_exit(int code) { exit(code); }
