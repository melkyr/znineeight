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
typedef __int64 i64_t;
typedef unsigned __int64 u64_t;
#else
typedef long long i64_t;
typedef unsigned long long u64_t;
#endif

#endif /* ZIG_RUNTIME_H */
