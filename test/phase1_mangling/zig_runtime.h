#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include <stddef.h>
#include "zig_compat.h"

/* Standard Zig-like primitive types mapped to C89 */
typedef signed char    i8;
typedef unsigned char  u8;
typedef short          i16;
typedef unsigned short u16;
typedef int            i32;
typedef unsigned int   u32;
typedef float          f32;
typedef double         f64;
typedef char           c_char;

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
void __bootstrap_panic(const char* msg, const char* file, int line);

/**
 * @brief Print helper for std.debug.print
 */
void __bootstrap_print(const char* s);

/**
 * @brief Print integer helper
 */
void __bootstrap_print_int(i32 n);

/**
 * @brief Print character helper
 */
void __bootstrap_print_char(i32 c);

/**
 * @brief Print bytes helper
 */
void __bootstrap_write(const char* s, usize len);

/* Arena Allocator API */
Arena* arena_create(usize initial_capacity);
void* arena_alloc(Arena* a, usize size);
void arena_reset(Arena* a);
void arena_destroy(Arena* a);

extern Arena* zig_default_arena;
void* arena_alloc_default(usize size);
void arena_free(void* ptr);

void __bootstrap_sleep_ms(unsigned int ms);

/* Networking (optional, requires linking net_runtime.o on Windows) */
int plat_socket_init(void);
void plat_socket_cleanup(void);
int plat_create_tcp_server(unsigned short port);
int plat_bind_listen(int sock, int backlog);
int plat_accept(int server_sock);
int plat_recv(int sock, u8* buf, int len);
int plat_send(int sock, const u8* buf, int len);
void plat_close_socket(int sock);
int plat_socket_select(int nfds, u8* readfds, u8* writefds, u8* exceptfds, int timeout_ms);
void plat_socket_fd_zero(u8* set);
void plat_socket_fd_set(int fd, u8* set);
int plat_socket_fd_isset(int fd, u8* set);

usize __bootstrap_usize_from_i64(i64 x);
bool plat_is_windows();

/* Runtime checked numeric conversions */

ZIG_INLINE ZIG_UNUSED i32 __bootstrap_i32_from_u32(u32 x) {
    if (x > 2147483647U) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}

ZIG_INLINE ZIG_UNUSED u32 __bootstrap_u32_from_u64(u64 x) {
    if (x > (u64)4294967295U) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}

ZIG_INLINE ZIG_UNUSED u32 __bootstrap_u32_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}

ZIG_INLINE ZIG_UNUSED usize __bootstrap_usize_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (usize)x;
}

ZIG_INLINE ZIG_UNUSED i32 __bootstrap_i32_from_usize(usize x) {
    if (x > 2147483647U) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}

ZIG_INLINE ZIG_UNUSED u8 __bootstrap_u8_from_usize(usize x) {
    if (x > 255) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (u8)x;
}

ZIG_INLINE ZIG_UNUSED u8 __bootstrap_u8_from_bool(bool b) {
    return (u8)b;
}

ZIG_INLINE ZIG_UNUSED f32 __bootstrap_f32_from_f64(double x) {
    return (f32)x;
}

ZIG_INLINE ZIG_UNUSED i32 __bootstrap_i32_from_u8(u8 x) {
    return (i32)x;
}

ZIG_INLINE ZIG_UNUSED u8 __bootstrap_u8_from_i32(i32 x) {
    if (x < 0 || x > 255) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u8)x;
}

ZIG_INLINE ZIG_UNUSED u8 __bootstrap_u8_from_u32(u32 x) {
    if (x > 255) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u8)x;
}

ZIG_INLINE ZIG_UNUSED u16 __bootstrap_u16_from_i32(i32 x) {
    if (x < 0 || x > 65535) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u16)x;
}

ZIG_INLINE ZIG_UNUSED u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u32)x;
}

ZIG_INLINE ZIG_UNUSED i8 __bootstrap_i8_from_i32(i32 x) {
    if (x < -128 || x > 127) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (i8)x;
}

ZIG_INLINE ZIG_UNUSED i16 __bootstrap_i16_from_i32(i32 x) {
    if (x < -32768 || x > 32767) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (i16)x;
}

ZIG_INLINE ZIG_UNUSED i32 __bootstrap_i32_from_i64(i64 x) {
    if (x < (i64)-2147483647 - 1 || x > (i64)2147483647) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (i32)x;
}

ZIG_INLINE ZIG_UNUSED c_char __bootstrap_c_char_from_u8(u8 x) {
    return (c_char)x;
}

#endif /* ZIG_RUNTIME_H */
