/* zig_runtime.c - Z98 Runtime Library (generated) */
#include "zig_compat.h"
#include <string.h>

/* Forward declarations for PAL functions */
extern void pal_print_stderr(const char* s, unsigned int len);
extern void pal_print_stdout(const char* s, unsigned int len);
extern void pal_abort(void);
extern void pal_trap(void);
extern int pal_i64_to_str(z64 val, char* buf, int bufsize);
extern int pal_u64_to_str(zu64 val, char* buf, int bufsize);
extern int pal_f64_to_str(double val, char* buf, int bufsize);

/* Panic handler */
void std_panic(const char* msg) {
    pal_print_stderr("panic: ", 7);
    pal_print_stderr(msg, strlen(msg));
    pal_print_stderr("\n", 1);
    pal_trap();
}

/* Print helpers */
void std_print(const char* s) { if (s) pal_print_stdout(s, strlen(s)); }
void std_print_len(const char* s, unsigned int len) { if (s && len) pal_print_stdout(s, len); }

/* The std_print_* formatting bodies moved to the Z98 std module
   sf/src/std_fmt.zig (std.fmt) in Task 1 of the print-formatting plan; the
   compiler now emits mangled std.fmt calls. std_print/std_print_len above
   remain the raw-bytes helpers (format-string literal segments, console). */

/* Backward compat I/O aliases __bootstrap_print* / __bootstrap_write /
   __bootstrap_sleep_ms / __bootstrap_panic REMOVED (F4, 2026-08-08) — the
   examples migrated to std.io (std_io.zig builtins). The cast helpers below
   call std_panic directly (operator ruling m0564). */

/* Checked conversions (u64 -> target type) */

signed char std_checked_cast_i8(zu64 val) {
    if (val > Z98_U64_C(127)) std_panic("int cast overflow for i8");
    return (signed char)val;
}

unsigned char std_checked_cast_u8(zu64 val) {
    if (val > Z98_U64_C(255)) std_panic("int cast overflow for u8");
    return (unsigned char)val;
}

short std_checked_cast_i16(zu64 val) {
    if (val > Z98_U64_C(32767)) std_panic("int cast overflow for i16");
    return (short)val;
}

unsigned short std_checked_cast_u16(zu64 val) {
    if (val > Z98_U64_C(65535)) std_panic("int cast overflow for u16");
    return (unsigned short)val;
}

int std_checked_cast_i32(zu64 val) {
    if (val > Z98_U64_C(2147483647)) std_panic("int cast overflow for i32");
    return (int)val;
}

unsigned int std_checked_cast_u32(zu64 val) {
    if (val > Z98_U64_C(4294967295)) std_panic("int cast overflow for u32");
    return (unsigned int)val;
}

z64 std_checked_cast_i64(zu64 val) {
    if (val > Z98_I64_MAX) std_panic("int cast overflow for i64");
    return (z64)val;
}

zu64 std_checked_cast_u64(zu64 val) {
    return val;
}

/* @intCast range-check helpers (F1, 2026-08-06).
   Copied from the zig0-oracle header (src/include/zig_runtime.h:96-185),
   standardized panic message: "integer cast overflow in @intCast".
   c_char is char; not typedef'd in zig_compat.h, so typedef'd here. */
typedef char c_char;

usize __bootstrap_usize_from_i64(i64 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (usize)x;
}

i32 __bootstrap_i32_from_u32(u32 x) {
    if (x > 2147483647U) std_panic("integer cast overflow in @intCast");
    return (i32)x;
}

u32 __bootstrap_u32_from_u64(u64 x) {
    if (x > (u64)4294967295U) std_panic("integer cast overflow in @intCast");
    return (u32)x;
}

usize __bootstrap_usize_from_u64(u64 x) {
    if (x > (u64)4294967295U) std_panic("integer cast overflow in @intCast");
    return (usize)x;
}

u32 __bootstrap_u32_from_i32(i32 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (u32)x;
}

usize __bootstrap_usize_from_i32(i32 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (usize)x;
}

i32 __bootstrap_i32_from_usize(usize x) {
    if (x > 2147483647U) std_panic("integer cast overflow in @intCast");
    return (i32)x;
}

u8 __bootstrap_u8_from_usize(usize x) {
    if (x > 255) std_panic("integer cast overflow in @intCast");
    return (u8)x;
}

u8 __bootstrap_u8_from_bool(bool b) {
    return (u8)b;
}

f32 __bootstrap_f32_from_f64(double x) {
    return (f32)x;
}

i32 __bootstrap_i32_from_u8(u8 x) {
    return (i32)x;
}

u8 __bootstrap_u8_from_i32(i32 x) {
    if (x < 0 || x > 255) std_panic("integer cast overflow in @intCast");
    return (u8)x;
}

u8 __bootstrap_u8_from_u32(u32 x) {
    if (x > 255) std_panic("integer cast overflow in @intCast");
    return (u8)x;
}

u16 __bootstrap_u16_from_i32(i32 x) {
    if (x < 0 || x > 65535) std_panic("integer cast overflow in @intCast");
    return (u16)x;
}

u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) std_panic("integer cast overflow in @intCast");
    return (u32)x;
}

u64 __bootstrap_u64_from_i64(i64 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (u64)x;
}

i8 __bootstrap_i8_from_i32(i32 x) {
    if (x < -128 || x > 127) std_panic("integer cast overflow in @intCast");
    return (i8)x;
}

i16 __bootstrap_i16_from_i32(i32 x) {
    if (x < -32768 || x > 32767) std_panic("integer cast overflow in @intCast");
    return (i16)x;
}

i32 __bootstrap_i32_from_i64(i64 x) {
    if (x < (i64)-2147483647 - 1 || x > (i64)2147483647) std_panic("integer cast overflow in @intCast");
    return (i32)x;
}

c_char __bootstrap_c_char_from_u8(u8 x) {
    return (c_char)x;
}

/* -fsafe undefined poison: byte-exact 0xAA fill. */
void zig_poison_fill(void* p, unsigned int n) {
    unsigned char* b = (unsigned char*)p;
    unsigned int i;
    for (i = 0; i < n; i++) {
        b[i] = (unsigned char)0xAAu;
    }
}

#if defined(_WIN32) && defined(ZIG_NO_CRT)
size_t strlen(const char* s) {
    const char* p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

void* memcpy(void* dst, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    const unsigned char* s = (const unsigned char*)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n;
        s += n;
        while (n--) *--d = *--s;
    }
    return dst;
}

void* memset(void* dst, int c, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    while (n--) *d++ = (unsigned char)c;
    return dst;
}

int strncmp(const char* a, const char* b, size_t n) {
    while (n--) {
        unsigned char ca = (unsigned char)*a++;
        unsigned char cb = (unsigned char)*b++;
        if (ca != cb) return (int)ca - (int)cb;
        if (ca == 0) return 0;
    }
    return 0;
}
#endif
