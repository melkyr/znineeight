#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include "zig_compat.h"

extern void pal_print_stderr(const char* s, unsigned int len);
extern void pal_abort(void);
extern void pal_trap(void);
extern int pal_i64_to_str(z64 val, char* buf, int bufsize);
extern int pal_u64_to_str(zu64 val, char* buf, int bufsize);
extern int pal_f64_to_str(double val, char* buf, int bufsize);

/* -fsafe undefined poison: byte-exact 0xAA fill (emitted only under -fsafe). */
void zig_poison_fill(void* p, unsigned int n);

/* -fsafe integer-overflow helpers (A15). The UB-free wrap/flag math lives
   here (header-static, like the __bootstrap_* cast helpers) so every
   emitted module is self-sufficient; the C89 emitter only maps the LIR
   *_with_overflow / overflow_flag ops to these calls. Emitted under -fsafe
   only, so -ffast output is byte-unchanged. */
static z64 zig_ovf_sext(zu64 x, unsigned int w) {
    zu64 m;
    if (w == 0u) return 0;
    if (w >= 64u) return (z64)x;
    m = (Z98_U64_C(1) << w) - Z98_U64_C(1);
    x = x & m;
    if ((x & (Z98_U64_C(1) << (w - 1u))) != Z98_U64_C(0)) x = x | (~m);
    return (z64)x;
}
static zu64 zig_ovf_mask(zu64 x, unsigned int w) {
    if (w == 0u) return 0;
    if (w >= 64u) return x;
    return x & ((Z98_U64_C(1) << w) - Z98_U64_C(1));
}
static zu64 zig_ovf_maxu(unsigned int w) {
    if (w >= 64u) return Z98_U64_MAX;
    return (Z98_U64_C(1) << w) - Z98_U64_C(1);
}
static z64 zig_ovf_maxs(unsigned int w) {
    if (w >= 64u) return Z98_I64_MAX;
    return (z64)((Z98_U64_C(1) << (w - 1u)) - Z98_U64_C(1));
}
static z64 zig_ovf_mins(unsigned int w) {
    if (w >= 64u) return Z98_I64_MIN;
    return -(z64)(Z98_U64_C(1) << (w - 1u));
}
static z64 zig_wrap_add_s(z64 a, z64 b, unsigned int w) {
    return zig_ovf_sext((zu64)a + (zu64)b, w);
}
static z64 zig_wrap_sub_s(z64 a, z64 b, unsigned int w) {
    return zig_ovf_sext((zu64)a - (zu64)b, w);
}
static z64 zig_wrap_mul_s(z64 a, z64 b, unsigned int w) {
    return zig_ovf_sext((zu64)a * (zu64)b, w);
}
static z64 zig_wrap_shl_s(z64 a, z64 b, unsigned int w) {
    return zig_ovf_sext(((zu64)a) << (((zu64)b) & Z98_U64_C(63)), w);
}
static z64 zig_wrap_neg_s(z64 a, unsigned int w) {
    return zig_ovf_sext((zu64)0 - (zu64)a, w);
}
static zu64 zig_wrap_add_u(zu64 a, zu64 b, unsigned int w) {
    return zig_ovf_mask(a + b, w);
}
static zu64 zig_wrap_sub_u(zu64 a, zu64 b, unsigned int w) {
    return zig_ovf_mask(a - b, w);
}
static zu64 zig_wrap_mul_u(zu64 a, zu64 b, unsigned int w) {
    return zig_ovf_mask(a * b, w);
}
static zu64 zig_wrap_shl_u(zu64 a, zu64 b, unsigned int w) {
    return zig_ovf_mask(a << (b & Z98_U64_C(63)), w);
}
static zu64 zig_wrap_neg_u(zu64 a, unsigned int w) {
    return zig_ovf_mask((zu64)0 - a, w);
}
static int zig_overflow_flag_add_s(z64 a, z64 b, unsigned int w) {
    z64 maxs = zig_ovf_maxs(w);
    z64 mins = zig_ovf_mins(w);
    if (b > 0 && a > maxs - b) return 1;
    if (b < 0 && a < mins - b) return 1;
    return 0;
}
static int zig_overflow_flag_add_u(zu64 a, zu64 b, unsigned int w) {
    return a > zig_ovf_maxu(w) - b;
}
static int zig_overflow_flag_sub_s(z64 a, z64 b, unsigned int w) {
    z64 maxs = zig_ovf_maxs(w);
    z64 mins = zig_ovf_mins(w);
    if (b < 0 && a > maxs + b) return 1;
    if (b > 0 && a < mins + b) return 1;
    return 0;
}
static int zig_overflow_flag_sub_u(zu64 a, zu64 b, unsigned int w) {
    (void)w;
    return a < b;
}
static int zig_overflow_flag_mul_s(z64 a, z64 b, unsigned int w) {
    z64 maxs = zig_ovf_maxs(w);
    z64 mins = zig_ovf_mins(w);
    if (a == 0 || b == 0) return 0;
    if (a > 0) {
        if (b > 0) return a > maxs / b;
        return b < mins / a;
    }
    if (b > 0) return a < mins / b;
    return a < maxs / b;
}
static int zig_overflow_flag_mul_u(zu64 a, zu64 b, unsigned int w) {
    if (b == Z98_U64_C(0)) return 0;
    return a > zig_ovf_maxu(w) / b;
}
static int zig_overflow_flag_shl_s(z64 a, z64 b, unsigned int w) {
    z64 maxs = zig_ovf_maxs(w);
    z64 mins = zig_ovf_mins(w);
    if (a == 0 || b <= 0) return 0;
    if (b >= (z64)w) return 1;
    return a > (maxs >> b) || a < (mins >> b);
}
static int zig_overflow_flag_shl_u(zu64 a, zu64 b, unsigned int w) {
    if (a == Z98_U64_C(0) || b == Z98_U64_C(0)) return 0;
    if (b >= (zu64)w) return 1;
    return a > (zig_ovf_maxu(w) >> b);
}
static int zig_overflow_flag_neg_s(z64 a, unsigned int w) {
    return a == zig_ovf_mins(w);
}
static int zig_overflow_flag_neg_u(zu64 a, unsigned int w) {
    (void)w;
    return a != Z98_U64_C(0);
}

/* Backward compat aliases __bootstrap_print* / __bootstrap_write /
   __bootstrap_sleep_ms / __bootstrap_panic REMOVED (F4, 2026-08-08) — the
   examples migrated to std.io (std_io.zig); the cast helpers below now call
   std_panic directly (operator ruling m0564). */

/* Arena */
void* arena_alloc_default(unsigned int size);
extern void* zig_default_arena;

void std_panic(const char* msg);
void std_print(const char* s);
void std_print_len(const char* s, unsigned int len);
void std_print_i32(int val);
void std_print_u32(unsigned int val);
void std_print_i64(z64 val);
void std_print_u64(zu64 val);
void std_print_f64(double val);
void std_print_bool(int val);
void std_print_char(unsigned char val);
void std_print_str(const unsigned char* ptr, unsigned int len);
void std_print_hex_u32(unsigned int val);
void std_print_hex_i32(int val);
void std_print_hex_u64(zu64 val);
void std_print_hex_i64(z64 val);
signed char std_checked_cast_i8(zu64 val);
unsigned char std_checked_cast_u8(zu64 val);
short std_checked_cast_i16(zu64 val);
unsigned short std_checked_cast_u16(zu64 val);
int std_checked_cast_i32(zu64 val);
unsigned int std_checked_cast_u32(zu64 val);
z64 std_checked_cast_i64(zu64 val);
zu64 std_checked_cast_u64(zu64 val);

/* @intCast range-check helpers (F1, 2026-08-06). Per-pair signed-aware;
   std_checked_cast_* is upper-bound-only and must NOT be used for @intCast
   (false-panics on in-range negatives). Defined `static` in this header so
   every emitted-C TU (single-stream and multi-module) is self-sufficient,
   and also as extern in zig_runtime.c for direct-linkers. Copied from the
   zig0-oracle header (src/include/zig_runtime.h:96-185), message standardized
   to "integer cast overflow in @intCast". */
typedef char c_char;
static usize __bootstrap_usize_from_i64(i64 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (usize)x;
}
static i32 __bootstrap_i32_from_u32(u32 x) {
    if (x > 2147483647U) std_panic("integer cast overflow in @intCast");
    return (i32)x;
}
static u32 __bootstrap_u32_from_u64(u64 x) {
    if (x > (u64)4294967295U) std_panic("integer cast overflow in @intCast");
    return (u32)x;
}
static usize __bootstrap_usize_from_u64(u64 x) {
    if (x > (u64)4294967295U) std_panic("integer cast overflow in @intCast");
    return (usize)x;
}
static u32 __bootstrap_u32_from_i32(i32 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (u32)x;
}
static usize __bootstrap_usize_from_i32(i32 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (usize)x;
}
static i32 __bootstrap_i32_from_usize(usize x) {
    if (x > 2147483647U) std_panic("integer cast overflow in @intCast");
    return (i32)x;
}
static u8 __bootstrap_u8_from_usize(usize x) {
    if (x > 255) std_panic("integer cast overflow in @intCast");
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
    if (x < 0 || x > 255) std_panic("integer cast overflow in @intCast");
    return (u8)x;
}
static u8 __bootstrap_u8_from_u32(u32 x) {
    if (x > 255) std_panic("integer cast overflow in @intCast");
    return (u8)x;
}
static u16 __bootstrap_u16_from_i32(i32 x) {
    if (x < 0 || x > 65535) std_panic("integer cast overflow in @intCast");
    return (u16)x;
}
static u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) std_panic("integer cast overflow in @intCast");
    return (u32)x;
}
static u64 __bootstrap_u64_from_i64(i64 x) {
    if (x < 0) std_panic("integer cast overflow in @intCast");
    return (u64)x;
}
static i8 __bootstrap_i8_from_i32(i32 x) {
    if (x < -128 || x > 127) std_panic("integer cast overflow in @intCast");
    return (i8)x;
}
static i16 __bootstrap_i16_from_i32(i32 x) {
    if (x < -32768 || x > 32767) std_panic("integer cast overflow in @intCast");
    return (i16)x;
}
static i32 __bootstrap_i32_from_i64(i64 x) {
    if (x < (i64)-2147483647 - 1 || x > (i64)2147483647) std_panic("integer cast overflow in @intCast");
    return (i32)x;
}
static c_char __bootstrap_c_char_from_u8(u8 x) {
    return (c_char)x;
}

/* -fsafe checked @intCast helpers (A18). The `int_cast_checked` LIR op carries
   src/dst signedness and widths, so the emitter only maps to these calls; the
   helper recovers the source value from (src_width, src_signed) and bound-checks
   it against the target width/sign. Header-static (like the __bootstrap_* cast
   helpers) so every emitted module is self-sufficient; emitted under -fsafe
   only, so -ffast output is byte-unchanged. Covers fixed-width and arbitrary
   `iN/uN` targets and the equal-width sign-change cases. */
static z64 zig_cast_checked_s(zu64 v, unsigned int sw, unsigned int ss, unsigned int dw) {
    z64 r;
    if (ss != 0u) r = zig_ovf_sext(v, sw); else r = (z64)zig_ovf_mask(v, sw);
    if (dw == 0u || dw > 64u) dw = 64u;
    if (dw >= 64u) {
        if (ss == 0u && r < 0) std_panic("integer cast overflow in @intCast");
        return r;
    }
    if (r < zig_ovf_mins(dw) || r > zig_ovf_maxs(dw)) std_panic("integer cast overflow in @intCast");
    return r;
}
static zu64 zig_cast_checked_u(zu64 v, unsigned int sw, unsigned int ss, unsigned int dw) {
    z64 r;
    zu64 m;
    if (ss != 0u) r = zig_ovf_sext(v, sw); else r = (z64)zig_ovf_mask(v, sw);
    if (ss != 0u) m = (zu64)r; else m = zig_ovf_mask(v, sw);
    if (dw == 0u || dw >= 64u) {
        if (ss != 0u && r < 0) std_panic("integer cast overflow in @intCast");
        return m;
    }
    if (r < 0 || (zu64)r > zig_ovf_maxu(dw)) std_panic("integer cast overflow in @intCast");
    return m;
}

#endif
