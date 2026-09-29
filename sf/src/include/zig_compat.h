/* zig_compat.h - C89 compatibility layer */
#ifndef ZIG_COMPAT_H
#define ZIG_COMPAT_H

/* FX14: the Z98 layout model is frozen at 32-bit (i64/u64/f64 size 8 align
   8). The era Windows compilers already default to that (MSVC /Zp8, wcc386
   -zp8), but gcc/clang/mingw on SysV i386 align 64-bit scalars to 4, so the
   shared typedefs below (and the emitted per-program carrier typedefs) carry
   this attribute to pin the model on every supported host compiler. */
#ifdef _MSC_VER
#define Z98_ALIGN8
#elif defined(__WATCOMC__)
#define Z98_ALIGN8
#else
#define Z98_ALIGN8 __attribute__((aligned(8)))
#endif

#ifdef _MSC_VER
    typedef __int64 z64 Z98_ALIGN8;
    typedef unsigned __int64 zu64 Z98_ALIGN8;
#elif defined(__WATCOMC__)
    typedef long long z64 Z98_ALIGN8;
    typedef unsigned long long zu64 Z98_ALIGN8;
#else
    typedef long long z64 Z98_ALIGN8;
    typedef unsigned long long zu64 Z98_ALIGN8;
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
    typedef double f64 Z98_ALIGN8;
    typedef unsigned int usize;
#endif

typedef int bool;
#define true 1
#define false 0

#ifndef NULL
#define NULL ((void*)0)
#endif

#if !defined(_WIN32)
#define Z98_STDCALL
#elif defined(_MSC_VER) || defined(__WATCOMC__)
#define Z98_STDCALL __stdcall
#else
#define Z98_STDCALL __attribute__((stdcall))
#endif

#endif /* ZIG_COMPAT_H */
