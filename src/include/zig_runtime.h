#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

/* Compatibility header for RetroZig bootstrap compiler output */

/*
 * 64-bit integer suffixes for non-MSVC compilers.
 * Note: These are intended to be used with the MSVC-style suffixes i64 and ui64.
 * While standard C89 does not support these as suffixes, we emit them for MSVC 6.0
 * compatibility and use these macros to aid other compilers if possible.
 */
#ifndef _MSC_VER
#define i64  LL
#define ui64 ULL
#endif

/* Standard types for the target C89 environment */
#ifdef _MSC_VER
/* MSVC 6.0 already has __int64 */
#else
/* Fallback for GCC/Clang in C89 mode */
#define __int64 long long
/* Provide i8, u8 etc if they aren't already available */
typedef signed char i8;
typedef unsigned char u8;
typedef short i16;
typedef unsigned short u16;
typedef int i32;
typedef unsigned int u32;
typedef __int64 i64;
typedef unsigned __int64 u64;
typedef unsigned int usize;
typedef int isize;
#endif

/* Runtime panic stub */
#include <stdlib.h>
#include <stdio.h>
static void __bootstrap_panic(const char* msg, const char* file, int line) {
    fprintf(stderr, "PANIC: %s at %s:%d\n", msg, file, line);
    abort();
}

#endif /* ZIG_RUNTIME_H */
