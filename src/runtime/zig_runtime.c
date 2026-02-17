#include "zig_runtime.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <stdlib.h>
#include <string.h>
#endif

/* Alignment requirement (8 bytes for safety on most architectures) */
#define ARENA_ALIGNMENT 8
#define ALIGN_UP(size, align) (((size) + (align) - 1) & ~((align) - 1))

/**
 * @struct ArenaBlock
 * @brief Internal block header for arena allocations.
 * Header is padded to ensure data starts at an 8-byte aligned offset.
 */
struct ArenaBlock {
    struct ArenaBlock* next;
    usize capacity;
    usize used;
    usize padding; /* Ensures 16-byte total header on 32-bit, 32-byte on 64-bit */
};

/* Global pointer to the default arena */
Arena* zig_default_arena = (Arena*)0;

/**
 * @brief Platform-specific allocation wrapper.
 */
static void* platform_alloc(usize size) {
#ifdef _WIN32
    /* Note: HeapAlloc on Win32 returns 8-byte aligned memory. */
    return HeapAlloc(GetProcessHeap(), 0, size);
#else
    return malloc(size);
#endif
}

/**
 * @brief Platform-specific free wrapper.
 */
static void platform_free(void* ptr) {
#ifdef _WIN32
    HeapFree(GetProcessHeap(), 0, ptr);
#else
    free(ptr);
#endif
}

Arena* arena_create(usize initial_capacity) {
    Arena* a = (Arena*)platform_alloc(sizeof(Arena));
    if (!a) return (Arena*)0;

    if (initial_capacity < 1024) {
        initial_capacity = 1024 * 16; /* Default 16KB if too small */
    }

    a->first = (ArenaBlock*)platform_alloc(initial_capacity + sizeof(ArenaBlock));
    if (!a->first) {
        platform_free(a);
        return (Arena*)0;
    }

    a->first->next = (ArenaBlock*)0;
    a->first->capacity = initial_capacity;
    a->first->used = 0;
    a->current = a->first;

    return a;
}

void* arena_alloc(Arena* a, usize size) {
    ArenaBlock* block;
    void* ptr;
    usize aligned_size = ALIGN_UP(size, ARENA_ALIGNMENT);

    /* Handle lazy initialization of the default arena */
    if (!a) {
        if (!zig_default_arena) {
            zig_default_arena = arena_create(1024 * 1024);
            if (!zig_default_arena) __bootstrap_panic("arena_alloc: Failed to init default arena", "zig_runtime.c", 82);
        }
        a = zig_default_arena;
    }

    block = a->current;
    if (block->used + aligned_size > block->capacity) {
        /* Need new block */
        usize next_cap = block->capacity * 2;
        ArenaBlock* next_block;
        if (next_cap < aligned_size) next_cap = aligned_size + 1024;

        next_block = (ArenaBlock*)platform_alloc(next_cap + sizeof(ArenaBlock));
        if (!next_block) __bootstrap_panic("arena_alloc: Out of memory", "zig_runtime.c", 95);

        next_block->next = (ArenaBlock*)0;
        next_block->capacity = next_cap;
        next_block->used = 0;

        block->next = next_block;
        a->current = next_block;
        block = next_block;
    }

    ptr = (void*)((char*)(block + 1) + block->used);
    block->used += aligned_size;
    return ptr;
}

void arena_reset(Arena* a) {
    ArenaBlock* curr;
    if (!a) return;
    curr = a->first;
    while (curr) {
        curr->used = 0;
        curr = curr->next;
    }
    a->current = a->first;
}

void arena_destroy(Arena* a) {
    ArenaBlock* curr;
    if (!a) return;
    curr = a->first;
    while (curr) {
        ArenaBlock* next = curr->next;
        platform_free(curr);
        curr = next;
    }
    platform_free(a);
}

void* arena_alloc_default(usize size) {
    return arena_alloc((Arena*)0, size);
}

void arena_free(void* ptr) {
    /* No-op: individual allocations cannot be freed in an arena. */
    (void)ptr;
}

void __bootstrap_print_int(i32 n) {
    char buf[32];
    int i = 0;
    unsigned int val;

    if (n < 0) {
        fputc('-', stderr);
        val = (unsigned int)(-n);
    } else {
        val = (unsigned int)n;
    }

    if (val == 0) {
        fputc('0', stderr);
        return;
    }

    /* Convert to decimal (reverse order) */
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }

    /* Reverse and print */
    while (i > 0) {
        fputc(buf[--i], stderr);
    }
}
