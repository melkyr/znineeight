#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef __cplusplus
/* Boolean support for C89 */
typedef int bool;
#define true 1
#define false 0
#endif

/* MSVC 6.0 specific hacks for 64-bit integers */
#ifdef _MSC_VER
    typedef __int64 i64;
    typedef unsigned __int64 u64;
#else
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
typedef float          f32;
typedef double         f64;

/**
 * @brief Macro to suppress "unused function" warnings in generated C code.
 */
#ifdef _MSC_VER
    #define RETR_UNUSED_FUNC
#else
    #define RETR_UNUSED_FUNC __attribute__((unused))
#endif

/* Pointer-sized integers */
#ifdef _WIN32
    typedef int isize;
    typedef unsigned int usize;
#else
    typedef long isize;
    typedef unsigned long usize;
#endif

/* Forward declaration for Arena structures */
typedef struct ArenaBlock ArenaBlock;

/**
 * @struct Arena
 * @brief Header for a linked-block arena allocator.
 */
typedef struct Arena {
    ArenaBlock* first;
    ArenaBlock* current;
} Arena;

/**
 * @brief Runtime panic handler.
 */
static void __bootstrap_panic(const char* msg, const char* file, int line) {
    fprintf(stderr, "PANIC: %s at %s:%d\n", msg, file, line);
    abort();
}

/**
 * @brief Print helper for std.debug.print
 */
static void __bootstrap_print(const char* s) {
    fputs(s, stderr);
}

/**
 * @brief Print integer helper
 */
void __bootstrap_print_int(i32 n);

/* Arena Allocator API */
Arena* arena_create(usize initial_capacity);
void* arena_alloc(Arena* a, usize size);
void arena_reset(Arena* a);
void arena_destroy(Arena* a);

extern Arena* zig_default_arena;
void* arena_alloc_default(usize size);
void arena_free(void* ptr);

/* Runtime checked numeric conversions */

static i32 __bootstrap_i32_from_u32(u32 x) {
    if (x > 2147483647U) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}

static i32 __bootstrap_i32_from_i64(i64 x) {
    if (x < (i64)-2147483647 - 1 || x > (i64)2147483647) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}

static u32 __bootstrap_u32_from_u64(u64 x) {
    if (x > (u64)4294967295U) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}

static u32 __bootstrap_u32_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}

static usize __bootstrap_usize_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (usize)x;
}

static i32 __bootstrap_i32_from_usize(usize x) {
    if (x > 2147483647U) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}

static u8 __bootstrap_u8_from_bool(bool b) {
    return (u8)b;
}

static f32 __bootstrap_f32_from_f64(double x) {
    return (f32)x;
}

#endif /* ZIG_RUNTIME_H */
