/* zig_nocrt.c - no-CRT stdio/time/env shim (emitted only under ZIG_NO_CRT). */
#include "zig_compat.h"

#if defined(_WIN32) && defined(ZIG_NO_CRT)

#include <stddef.h>
#include <windows.h>
#if defined(_MSC_VER) || defined(__WATCOMC__)
#include <stdio.h>
#else
typedef struct _z98_FILE FILE;
static char g_iob[3];
#endif

extern const char* pal_getenv(const char* name);
extern z64 pal_wallclock_unix(void);

#if defined(_MSC_VER)
FILE _iob[3];
#elif defined(__WATCOMC__)
__w_FILE __iob[3];
#endif

#undef getchar
#undef putchar
#undef getc
#undef putc

#if !defined(_MSC_VER) && !defined(__WATCOMC__)
FILE* __acrt_iob_func(unsigned idx) {
    if (idx > 2u) return (FILE*)0;
    return (FILE*)&g_iob[idx];
}
__asm__(".section .data,\"w\"");
__asm__(".globl __imp____acrt_iob_func");
__asm__("__imp____acrt_iob_func:");
__asm__(".long ___acrt_iob_func");
__asm__(".text");
#endif

static HANDLE z98_stream_handle(FILE* stream) {
#if defined(_MSC_VER)
    if (stream == &_iob[2]) return GetStdHandle(STD_ERROR_HANDLE);
#elif defined(__WATCOMC__)
    if (stream == &__iob[2]) return GetStdHandle(STD_ERROR_HANDLE);
#else
    if (stream == __acrt_iob_func(2u)) return GetStdHandle(STD_ERROR_HANDLE);
#endif
    return GetStdHandle(STD_OUTPUT_HANDLE);
}

size_t fwrite(const void* p, size_t sz, size_t n, FILE* stream) {
    size_t total = sz * n;
    size_t off = 0;
    HANDLE h;
    if (total == 0) return 0;
    h = z98_stream_handle(stream);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return 0;
    while (off < total) {
        DWORD chunk = (DWORD)(total - off);
        DWORD wrote = 0;
        if (!WriteConsoleA(h, (const char*)p + off, chunk, &wrote, NULL)) {
            if (!WriteFile(h, (const char*)p + off, chunk, &wrote, NULL)) return 0;
        }
        if (wrote == 0) return 0;
        off += (size_t)wrote;
    }
    return n;
}

int getchar(void) {
    char ch;
    DWORD r = 0;
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return -1;
    if (!ReadFile(h, &ch, 1, &r, NULL) || r == 0) return -1;
    return (unsigned char)ch;
}

int getc(FILE* stream) {
    (void)stream;
    return getchar();
}

int fgetc(FILE* stream) {
    return getc(stream);
}

int putchar(int c) {
    char ch = (char)c;
    DWORD w = 0;
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return -1;
    if (!WriteConsoleA(h, &ch, 1, &w, NULL)) {
        if (!WriteFile(h, &ch, 1, &w, NULL)) return -1;
    }
    return (unsigned char)c;
}

int putc(int c, FILE* stream) {
    char ch = (char)c;
    DWORD w = 0;
    HANDLE h = z98_stream_handle(stream);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return -1;
    if (!WriteConsoleA(h, &ch, 1, &w, NULL)) {
        if (!WriteFile(h, &ch, 1, &w, NULL)) return -1;
    }
    return (unsigned char)c;
}

int fputc(int c, FILE* stream) {
    return putc(c, stream);
}

int _filbuf(FILE* stream) {
    (void)stream;
    return getchar();
}

int _flsbuf(int c, FILE* stream) {
    return putc(c, stream);
}

char* getenv(const char* name) {
    return (char*)pal_getenv(name);
}

long _time32(long* t) {
    long v = (long)pal_wallclock_unix();
    if (t) *t = v;
    return v;
}

long time(long* t) {
    return _time32(t);
}

#if !defined(_MSC_VER) && !defined(__WATCOMC__)
__asm__(".section .data,\"w\"");
__asm__(".globl __imp___time32");
__asm__("__imp___time32:");
__asm__(".long __time32");
__asm__(".text");
#endif

#else
typedef int zig_nocrt_dummy;
#endif
