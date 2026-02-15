#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include <stddef.h>  /* for size_t (C89 may not have it, but MSVC 6.0 does) */

/* Boolean support for C89 */
typedef int bool;
#define true 1
#define false 0

/* MSVC 6.0 specific hacks for 64-bit integers */
#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
#else
    /* For GCC/other C89 compilers, we assume they support long long or
       provide int64 via a similar mechanism. */
    typedef long long i64;
    typedef unsigned long long u64;
#endif

/* Standard Zig-like primitive types mapped to C89 */
typedef signed char    i8;
typedef unsigned char  u8;
typedef short          i16;
typedef unsigned short u16;
typedef int            i32;
typedef unsigned int   u32;

/* Pointer-sized integers */
#ifdef _WIN32
    typedef int isize;
    typedef unsigned int usize;
#else
    /* For other platforms, we might need different types,
       but bootstrap assumes 32-bit for now. */
    typedef long isize;
    typedef unsigned long usize;
#endif

/* Panic function (to be implemented later) */
void __bootstrap_panic(const char* msg);

/* Declarations for runtime helpers (to be added as needed) */

#endif /* ZIG_RUNTIME_H */
