/* zig_runtime.c - Z98 Runtime Library (generated) */
#include "zig_compat.h"
#include <string.h>

/* Forward declarations for PAL functions */
extern void pal_print_stderr(const char* s, unsigned int len);
extern void pal_print_stdout(const char* s, unsigned int len);
extern void pal_abort(void);
extern int pal_i64_to_str(long long val, char* buf, int bufsize);
extern int pal_u64_to_str(unsigned long long val, char* buf, int bufsize);
extern int pal_f64_to_str(double val, char* buf, int bufsize);

/* Panic handler */
void std_panic(const char* msg) {
    pal_print_stderr("panic: ", 7);
    pal_print_stderr(msg, strlen(msg));
    pal_print_stderr("\n", 1);
    pal_abort();
}

/* Print helpers */
void std_print(const char* s) { if (s) pal_print_stdout(s, strlen(s)); }
void std_print_len(const char* s, unsigned int len) { if (s && len) pal_print_stdout(s, len); }

void std_print_i32(int val) {
    char buf[16];
    pal_i64_to_str((long long)val, buf, sizeof(buf));
    std_print(buf);
}

void std_print_u32(unsigned int val) {
    char buf[16];
    pal_u64_to_str((unsigned long long)val, buf, sizeof(buf));
    std_print(buf);
}

void std_print_i64(long long val) {
    char buf[24];
    pal_i64_to_str(val, buf, sizeof(buf));
    std_print(buf);
}

void std_print_u64(unsigned long long val) {
    char buf[24];
    pal_u64_to_str(val, buf, sizeof(buf));
    std_print(buf);
}

void std_print_f64(double val) {
    char buf[32];
    pal_f64_to_str(val, buf, sizeof(buf));
    std_print(buf);
}

void std_print_bool(int val) {
    if (val) std_print("true");
    else std_print("false");
}

void std_print_char(unsigned char val) { char c = (char)val; pal_print_stdout(&c, 1); }

void std_print_str(const unsigned char* ptr, unsigned int len) {
    if (ptr && len) pal_print_stdout((const char*)ptr, len);
}

/* Backward compat I/O aliases __bootstrap_print* / __bootstrap_write /
   __bootstrap_sleep_ms / __bootstrap_panic REMOVED (F4, 2026-08-08) — the
   examples migrated to std.io (std_io.zig builtins). The cast helpers below
   call std_panic directly (operator ruling m0564). */

/* Checked conversions (u64 -> target type) */

signed char std_checked_cast_i8(unsigned long long val) {
    if (val > 127ULL) std_panic("int cast overflow for i8");
    return (signed char)val;
}

unsigned char std_checked_cast_u8(unsigned long long val) {
    if (val > 255ULL) std_panic("int cast overflow for u8");
    return (unsigned char)val;
}

short std_checked_cast_i16(unsigned long long val) {
    if (val > 32767ULL) std_panic("int cast overflow for i16");
    return (short)val;
}

unsigned short std_checked_cast_u16(unsigned long long val) {
    if (val > 65535ULL) std_panic("int cast overflow for u16");
    return (unsigned short)val;
}

int std_checked_cast_i32(unsigned long long val) {
    if (val > 2147483647ULL) std_panic("int cast overflow for i32");
    return (int)val;
}

unsigned int std_checked_cast_u32(unsigned long long val) {
    if (val > 4294967295ULL) std_panic("int cast overflow for u32");
    return (unsigned int)val;
}

long long std_checked_cast_i64(unsigned long long val) {
    if (val > 9223372036854775807ULL) std_panic("int cast overflow for i64");
    return (long long)val;
}

unsigned long long std_checked_cast_u64(unsigned long long val) {
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
