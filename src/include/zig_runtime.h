#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include <stddef.h>  /* for size_t (C89 may not have it, but MSVC 6.0 does) */
#include <stdio.h>
#include <stdlib.h>

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
typedef float          f32;
typedef double         f64;

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

/* Panic function */
static void __bootstrap_panic(const char* msg) {
    fputs("panic: ", stderr);
    fputs(msg, stderr);
    fputc('\n', stderr);
/**
 * @brief Runtime panic handler.
 *
 * This function is called when a runtime safety check fails (e.g., integer
 * overflow in @intCast, which will be implemented in Milestone 5 Phase 2).
 * It prints an error message to stderr and aborts execution.
 *
 * @param msg The error message to display.
 * @param file The source file where the panic occurred.
 * @param line The line number where the panic occurred.
 */
#include <stdlib.h>
#include <stdio.h>

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
 * @brief Creates a new arena with the specified initial capacity.
 * @param initial_capacity The size of the first block in bytes.
 * @return A pointer to the newly created arena, or NULL on failure.
 */
Arena* arena_create(usize initial_capacity);

/**
 * @brief Allocates memory from the specified arena.
 * @param a The arena to allocate from.
 * @param size The number of bytes to allocate.
 * @return A pointer to the allocated memory. Panics on failure.
 */
void* arena_alloc(Arena* a, usize size);

/**
 * @brief Resets the arena, making all its memory available for reuse.
 * Does not free the blocks back to the OS.
 * @param a The arena to reset.
 */
void arena_reset(Arena* a);

/**
 * @brief Destroys the arena and frees all its memory back to the OS.
 * @param a The arena to destroy.
 */
void arena_destroy(Arena* a);

/**
 * @brief Default global arena for simple allocations.
 * Initialized at program startup.
 */
extern Arena* zig_default_arena;

/**
 * @brief Convenience wrapper for allocating from the default arena.
 * Used for backward compatibility with Milestone 4 tests.
 */
void* arena_alloc_default(usize size);

/**
 * @brief Frees memory. For arenas, this is a no-op.
 * Provided for compatibility with tests.
 */
void arena_free(void* ptr);

static void __bootstrap_panic(const char* msg, const char* file, int line) {
    fprintf(stderr, "PANIC: %s at %s:%d\n", msg, file, line);
    abort();
}

/* Print helper for std.debug.print */
static void __bootstrap_print(const char* s) {
    fputs(s, stderr);
}

/* Runtime checked numeric conversions */

static i32 __bootstrap_i32_from_u32(u32 x) {
    if (x > 2147483647U) __bootstrap_panic("integer overflow in @intCast");
    return (i32)x;
}

static i32 __bootstrap_i32_from_i64(i64 x) {
    if (x < (i64)-2147483647 - 1 || x > (i64)2147483647) __bootstrap_panic("integer overflow in @intCast");
    return (i32)x;
}

static u32 __bootstrap_u32_from_u64(u64 x) {
    /* 4294967295U is 0xFFFFFFFF, which is the maximum value for u32 on our 32-bit target */
    if (x > (u64)4294967295U) __bootstrap_panic("integer overflow in @intCast");
    return (u32)x;
}

static u32 __bootstrap_u32_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer overflow in @intCast");
    return (u32)x;
}

static u8 __bootstrap_u8_from_bool(bool b) {
    /* bool is int, should be 0 or 1. */
    return (u8)b;
}

static f32 __bootstrap_f32_from_f64(double x) {
    /* We don't perform strict range checks for float narrowing in bootstrap */
    return (f32)x;
}

#endif /* ZIG_RUNTIME_H */
