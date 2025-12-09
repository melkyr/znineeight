#ifndef COMMON_HPP
#define COMMON_HPP

/**
 * @file common.hpp
 * @brief Provides compatibility definitions for MSVC 6.0 and modern C++ compilers.
 *
 * This header addresses two main compatibility issues with the MSVC 6.0 (Visual C++ 98) toolchain:
 * 1. Lack of standard fixed-width integer types (e.g., `int64_t`).
 * 2. Non-standard handling of the `bool` type.
 *
 * By including this file, the rest of the codebase can use types like `i64` and `u32`
 * consistently, regardless of the underlying compiler.
 */

// MSVC 6.0 specific integer handling
#ifdef _MSC_VER
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
#else
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

// Boolean support for pre-standard C++
#ifdef _MSC_VER
    #ifndef bool
        /**
         * @brief Defines `bool`, `true`, and `false` for MSVC 6.0, which lacks a built-in bool type.
         */
        typedef int bool;
        #define true 1
        #define false 0
    #endif
#endif

#endif // COMMON_HPP
