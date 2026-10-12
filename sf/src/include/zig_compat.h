/* zig_compat.h - C89 compatibility layer */
#ifndef ZIG_COMPAT_H
#define ZIG_COMPAT_H

#ifdef _MSC_VER
    typedef __int64 z64;
    typedef unsigned __int64 zu64;
#elif defined(__WATCOMC__)
    typedef long long z64;
    typedef unsigned long long zu64;
#else
    typedef long long z64;
    typedef unsigned long long zu64;
#endif

#if !defined(__cplusplus) && !defined(__WATCOMC__)
    typedef signed char i8;
    typedef short i16;
    typedef int i32;
    typedef z64 i64;
    typedef unsigned char u8;
    typedef unsigned short u16;
    typedef unsigned int u32;
    typedef zu64 u64;
    typedef float f32;
    typedef double f64;
    typedef unsigned int usize;
#endif

typedef int bool;
#define true 1
#define false 0

#ifndef NULL
#define NULL ((void*)0)
#endif

#endif /* ZIG_COMPAT_H */
