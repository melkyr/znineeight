#ifndef ZIG_COMPAT_HPP
#define ZIG_COMPAT_HPP

/**
 * @file compat.hpp
 * @brief Preprocessor Compatibility Layer for Z98 Bootstrap Compiler.
 *
 * This header abstracts compiler and target differences to ensure the
 * bootstrap compiler (zig0) can be built with legacy C++98 compilers
 * (MSVC 6.0, OpenWatcom) and modern ones.
 */

/* Include C header for size_t, NULL. Works on all target platforms. */
#include <stddef.h>

/* Detect compilers */
#ifdef _MSC_VER
    #define ZIG_COMPILER_MSVC
    #if _MSC_VER == 1200 /* MSVC 6.0 */
        #define ZIG_COMPILER_MSVC6
    #endif
#elif defined(__WATCOMC__)
    #define ZIG_COMPILER_OPENWATCOM
#endif

/* Fixed-width integer types */
#ifdef ZIG_COMPILER_MSVC
    /** @brief 64-bit signed integer. */
    typedef __int64 i64;
    /** @brief 64-bit unsigned integer. */
    typedef unsigned __int64 u64;
    /** @brief 32-bit signed integer. */
    typedef int i32;
    /** @brief 32-bit unsigned integer. */
    typedef unsigned int u32;
    /** @brief 16-bit signed integer. */
    typedef short i16;
    /** @brief 16-bit unsigned integer. */
    typedef unsigned short u16;
    /** @brief 8-bit signed integer. */
    typedef signed char i8;
    /** @brief 8-bit unsigned integer. */
    typedef unsigned char u8;
#elif defined(ZIG_COMPILER_OPENWATCOM)
    /* OpenWatcom supports long long as an extension */
    typedef long long i64;
    typedef unsigned long long u64;
    typedef int i32;
    typedef unsigned int u32;
    typedef short i16;
    typedef unsigned short u16;
    typedef signed char i8;
    typedef unsigned char u8;
#else
    /* Assume C99/C++11 or presence of <stdint.h> */
    #include <stdint.h>
    typedef int64_t i64;
    typedef uint64_t u64;
    typedef int32_t i32;
    typedef uint32_t u32;
    typedef int16_t i16;
    typedef uint16_t u16;
    typedef int8_t i8;
    typedef uint8_t u8;
#endif

/* Boolean support for pre-standard C++ (Compiler Source) */
#ifdef ZIG_COMPILER_MSVC
    #ifndef __cplusplus
        #ifndef bool
            typedef int bool;
            #define true 1
            #define false 0
        #endif
    #endif
#endif

/* inline keyword abstraction */
#ifdef ZIG_COMPILER_MSVC
    #define ZIG_INLINE __inline
#else
    #define ZIG_INLINE inline
#endif

/* 64-bit integer suffix for literals in generated C */
#ifdef ZIG_COMPILER_MSVC
    #define ZIG_I64_SUFFIX "i64"
    #define ZIG_UI64_SUFFIX "ui64"
#else
    #define ZIG_I64_SUFFIX "LL"
    #define ZIG_UI64_SUFFIX "ULL"
#endif

/* Unused parameter/variable macro */
#ifndef RETR_UNUSED
    #define RETR_UNUSED(x) (void)(x)
#endif

/* Unused function macro */
#ifdef ZIG_COMPILER_MSVC
    #define RETR_UNUSED_FUNC
#else
    #define RETR_UNUSED_FUNC __attribute__((unused))
#endif

#endif /* ZIG_COMPAT_HPP */
