#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include <stddef.h>  /* for size_t (C89 may not have it, but MSVC 6.0 does) */

/* Boolean support for C89 */
typedef int bool;
#define true 1
#define false 0

/* MSVC 6.0 specific hacks for 64-bit integers */
#ifdef _MSC_VER
    typedef __int64 i64_t;
    typedef unsigned __int64 u64_t;
#else
    /* For GCC/other C89 compilers, we assume they support long long or
       provide int64_t via a similar mechanism. */
    typedef long long i64_t;
    typedef unsigned long long u64_t;
#endif

/* Standard Zig-like primitive types mapped to C89 */
typedef signed char    i8_t;
typedef unsigned char  u8_t;
typedef short          i16_t;
typedef unsigned short u16_t;
typedef int            i32_t;
typedef unsigned int   u32_t;

/* Panic function (to be implemented later) */
void __bootstrap_panic(const char* msg);

/* Declarations for runtime helpers (to be added as needed) */

#endif /* ZIG_RUNTIME_H */
