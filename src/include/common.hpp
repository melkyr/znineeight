#ifndef COMMON_HPP
#define COMMON_HPP
// MSVC 6.0 specific integer handling
#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
    typedef int i32;
    typedef unsigned int u32;
    typedef short i16;
    typedef unsigned short u16;
    typedef signed char i8;
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
    typedef int bool;
    #define true 1
    #define false 0
    #endif
#endif
#endif // COMMON_HPP
