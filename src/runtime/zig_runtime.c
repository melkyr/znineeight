#include "zig_runtime.h"
#include <string.h>
#include <stdlib.h>

#ifdef _WIN32
#include "platform_win98.h"
#include <windows.h>
#else
#include <unistd.h>
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
    if (size == 0) return (void*)0;
    if (size > 4 * 1024 * 1024) {  /* > 4 MB */
        /* VirtualAlloc gives page-aligned memory, suitable for large blocks */
        return VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    } else {
        /* Note: HeapAlloc on Win32 returns 8-byte aligned memory. */
        return HeapAlloc(GetProcessHeap(), 0, size);
    }
#else
    return malloc(size);
#endif
}

/**
 * @brief Platform-specific free wrapper.
 */
static void platform_free(void* ptr) {
    if (!ptr) return;
#ifdef _WIN32
    /* Freeing a VirtualAlloc block requires VirtualFree */
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(ptr, &mbi, sizeof(mbi)) && mbi.AllocationBase == ptr) {
        VirtualFree(ptr, 0, MEM_RELEASE);
    } else {
        HeapFree(GetProcessHeap(), 0, ptr);
    }
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

void __bootstrap_write(const char* s, usize len) {
    if (!s || len == 0) return;
#ifdef _WIN32
    {
        HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD written = 0;
        if (hOut == INVALID_HANDLE_VALUE || hOut == NULL) {
            /* Fallback to stderr if stdout is invalid (rare) */
            hOut = GetStdHandle(STD_ERROR_HANDLE);
            if (hOut == INVALID_HANDLE_VALUE || hOut == NULL) return;
        }

        /* Try WriteConsoleA first - it works better with Win9x console */
        if (!WriteConsoleA(hOut, (LPCSTR)s, (DWORD)len, &written, NULL)) {
            /* Fallback to WriteFile for redirected output */
            WriteFile(hOut, (const void*)s, (DWORD)len, &written, NULL);
        }
    }
#else
    /* Unix: write to stdout (fd 1) */
    {
        size_t total_written = 0;
        while (total_written < len) {
            ssize_t written = write(1, s + total_written, len - total_written);
            if (written <= 0) break;
            total_written += (size_t)written;
        }
    }
#endif
}

void __bootstrap_print(const char* s) {
    if (!s) return;
    __bootstrap_write(s, strlen(s));
}

void __bootstrap_panic(const char* msg, const char* file, int line) {
    char buf[32];
    int i = 0;
    unsigned int val;

    __bootstrap_print("PANIC: ");
    __bootstrap_print(msg);
    __bootstrap_print(" at ");
    __bootstrap_print(file);
    __bootstrap_print(":");

    val = (unsigned int)line;
    if (val == 0) {
        __bootstrap_print("0");
    } else {
        while (val > 0) {
            buf[i++] = '0' + (val % 10);
            val /= 10;
        }
        while (i > 0) {
            char c = buf[--i];
            char s[2];
            s[0] = c;
            s[1] = '\0';
            __bootstrap_print(s);
        }
    }
    __bootstrap_print("\n");
    abort();
}

void __bootstrap_print_int(i32 n) {
    char buf[32];
    int i = 0;
    unsigned int val;

    if (n < 0) {
        __bootstrap_print("-");
        val = (unsigned int)(-n);
    } else {
        val = (unsigned int)n;
    }

    if (val == 0) {
        __bootstrap_print("0");
        return;
    }

    /* Convert to decimal (reverse order) */
    while (val > 0) {
        buf[i++] = '0' + (val % 10);
        val /= 10;
    }

    /* Reverse and print */
    while (i > 0) {
        char c = buf[--i];
        char s[2];
        s[0] = c;
        s[1] = '\0';
        __bootstrap_print(s);
    }
}

void __bootstrap_print_char(i32 c) {
    char s[2];
    s[0] = (char)c;
    s[1] = '\0';
    __bootstrap_print(s);
}


u8 __bootstrap_u8_from_usize(usize x) {
    if (x > 255) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (u8)x;
}

usize __bootstrap_usize_from_i64(i64 x) {
    if (x < 0) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (usize)x;
}
