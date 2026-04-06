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

/* inline keyword abstraction */
#ifdef _MSC_VER
    #define ZIG_INLINE __inline
#else
    /* C89 does not have inline. Modern compilers often support it as an extension.
       For strict C89, we expand to empty. */
    #ifdef __STDC_VERSION__
        #if __STDC_VERSION__ >= 199901L
            #define ZIG_INLINE inline
        #else
            #define ZIG_INLINE
        #endif
    #else
        #define ZIG_INLINE
    #endif
#endif

#endif /* ZIG_COMPAT_H */
