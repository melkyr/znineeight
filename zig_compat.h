#ifndef ZIG_COMPAT_H
#define ZIG_COMPAT_H

/**
 * @file zig_compat.h
 * @brief C89 Compatibility Layer for Generated C code.
 */

#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
#elif defined(__WATCOMC__)
    /* OpenWatcom supports long long as an extension */
    typedef long long i64;
    typedef unsigned long long u64;
#else
    /* Use long long for other compilers, assuming they support it as an extension in C89 mode */
    typedef long long i64;
    typedef unsigned long long u64;
#endif

#ifndef __cplusplus
    /* Boolean support for strict C89 */
    typedef int bool;
    #define true 1
    #define false 0
#endif

/* Inline keyword abstraction for C89.
   We use 'static' to allow the compiler to inline if it chooses,
   while remaining strictly C89 compliant. */
#ifdef _MSC_VER
    #define ZIG_INLINE static __inline
#elif defined(__GNUC__)
    #define ZIG_INLINE static __inline__
#else
    #define ZIG_INLINE static
#endif

/* Unused function macro for generated C code */
#ifdef __GNUC__
    #define ZIG_UNUSED __attribute__((unused))
#else
    #define ZIG_UNUSED
#endif

#endif /* ZIG_COMPAT_H */
