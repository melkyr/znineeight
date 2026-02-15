/* zig_runtime.h - Minimal runtime for RetroZig first program */
#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

/* Don't include stdio.h to avoid conflict with our emission of puts */

/* Basic types */
typedef int bool;
#define true 1
#define false 0

typedef signed char i8;
typedef unsigned char u8;
typedef short i16;
typedef unsigned short u16;
typedef int i32;
typedef unsigned int u32;

#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
#else
    typedef long long i64;
    typedef unsigned long long u64;
#endif

typedef int isize;
typedef unsigned int usize;

/* Panic handler */
static void __bootstrap_panic(const char* msg) {
}

#endif /* ZIG_RUNTIME_H */
