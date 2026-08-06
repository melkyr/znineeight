#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include "zig_compat.h"

extern void pal_print_stderr(const char* s, unsigned int len);
extern void pal_abort(void);
extern int pal_i64_to_str(long long val, char* buf, int bufsize);
extern int pal_u64_to_str(unsigned long long val, char* buf, int bufsize);
extern int pal_f64_to_str(double val, char* buf, int bufsize);

/* Backward compat aliases — defined in zig_runtime.c */
void __bootstrap_print(const char* s);
void __bootstrap_print_int(int n);
void __bootstrap_print_char(int c);
void __bootstrap_panic(const char* msg, const char* file, int line);
void __bootstrap_write(const char* s, unsigned int len);
void __bootstrap_sleep_ms(unsigned int ms);

/* Arena */
void* arena_alloc_default(unsigned int size);
extern void* zig_default_arena;

void std_panic(const char* msg);
void std_print(const char* s);
void std_print_len(const char* s, unsigned int len);
void std_print_i32(int val);
void std_print_u32(unsigned int val);
void std_print_i64(long long val);
void std_print_u64(unsigned long long val);
void std_print_f64(double val);
void std_print_bool(int val);
void std_print_char(unsigned char val);
void std_print_str(const unsigned char* ptr, unsigned int len);
signed char std_checked_cast_i8(unsigned long long val);
unsigned char std_checked_cast_u8(unsigned long long val);
short std_checked_cast_i16(unsigned long long val);
unsigned short std_checked_cast_u16(unsigned long long val);
int std_checked_cast_i32(unsigned long long val);
unsigned int std_checked_cast_u32(unsigned long long val);
long long std_checked_cast_i64(unsigned long long val);
unsigned long long std_checked_cast_u64(unsigned long long val);

/* @intCast range-check helpers (F1, 2026-08-06). Per-pair signed-aware;
   std_checked_cast_* is upper-bound-only and must NOT be used for @intCast
   (false-panics on in-range negatives). Defined `static` in this header so
   every emitted-C TU (single-stream and multi-module) is self-sufficient,
   and also as extern in zig_runtime.c for direct-linkers. Copied from the
   zig0-oracle header (src/include/zig_runtime.h:96-185), message standardized
   to "integer cast overflow in @intCast". */
typedef char c_char;
static usize __bootstrap_usize_from_i64(i64 x) {
    if (x < 0) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (usize)x;
}
static i32 __bootstrap_i32_from_u32(u32 x) {
    if (x > 2147483647U) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}
static u32 __bootstrap_u32_from_u64(u64 x) {
    if (x > (u64)4294967295U) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}
static u32 __bootstrap_u32_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}
static usize __bootstrap_usize_from_i32(i32 x) {
    if (x < 0) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (usize)x;
}
static i32 __bootstrap_i32_from_usize(usize x) {
    if (x > 2147483647U) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}
static u8 __bootstrap_u8_from_usize(usize x) {
    if (x > 255) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u8)x;
}
static u8 __bootstrap_u8_from_bool(bool b) {
    return (u8)b;
}
static f32 __bootstrap_f32_from_f64(double x) {
    return (f32)x;
}
static i32 __bootstrap_i32_from_u8(u8 x) {
    return (i32)x;
}
static u8 __bootstrap_u8_from_i32(i32 x) {
    if (x < 0 || x > 255) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u8)x;
}
static u8 __bootstrap_u8_from_u32(u32 x) {
    if (x > 255) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u8)x;
}
static u16 __bootstrap_u16_from_i32(i32 x) {
    if (x < 0 || x > 65535) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u16)x;
}
static u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u32)x;
}
static u64 __bootstrap_u64_from_i64(i64 x) {
    if (x < 0) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (u64)x;
}
static i8 __bootstrap_i8_from_i32(i32 x) {
    if (x < -128 || x > 127) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (i8)x;
}
static i16 __bootstrap_i16_from_i32(i32 x) {
    if (x < -32768 || x > 32767) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (i16)x;
}
static i32 __bootstrap_i32_from_i64(i64 x) {
    if (x < (i64)-2147483647 - 1 || x > (i64)2147483647) __bootstrap_panic("integer cast overflow in @intCast", __FILE__, __LINE__);
    return (i32)x;
}
static c_char __bootstrap_c_char_from_u8(u8 x) {
    return (c_char)x;
}

#endif
