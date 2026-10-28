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

/* -fsafe integer-overflow helpers (A15). The UB-free wrap/flag math is
   defined once in zig_runtime.c (external linkage) and declared here so
   every emitted module can call it without a per-TU static copy. The C89
   emitter only maps the LIR *_with_overflow / overflow_flag ops to these
   calls. Emitted under -fsafe only, so -ffast output is byte-unchanged. */
z64 zig_ovf_sext(zu64 x, unsigned int w);
zu64 zig_ovf_mask(zu64 x, unsigned int w);
zu64 zig_ovf_maxu(unsigned int w);
z64 zig_ovf_maxs(unsigned int w);
z64 zig_ovf_mins(unsigned int w);
z64 zig_wrap_add_s(z64 a, z64 b, unsigned int w);
z64 zig_wrap_sub_s(z64 a, z64 b, unsigned int w);
z64 zig_wrap_mul_s(z64 a, z64 b, unsigned int w);
z64 zig_wrap_shl_s(z64 a, z64 b, unsigned int w);
z64 zig_wrap_neg_s(z64 a, unsigned int w);
zu64 zig_wrap_add_u(zu64 a, zu64 b, unsigned int w);
zu64 zig_wrap_sub_u(zu64 a, zu64 b, unsigned int w);
zu64 zig_wrap_mul_u(zu64 a, zu64 b, unsigned int w);
zu64 zig_wrap_shl_u(zu64 a, zu64 b, unsigned int w);
zu64 zig_wrap_neg_u(zu64 a, unsigned int w);
int zig_overflow_flag_add_s(z64 a, z64 b, unsigned int w);
int zig_overflow_flag_add_u(zu64 a, zu64 b, unsigned int w);
int zig_overflow_flag_sub_s(z64 a, z64 b, unsigned int w);
int zig_overflow_flag_sub_u(zu64 a, zu64 b, unsigned int w);
int zig_overflow_flag_mul_s(z64 a, z64 b, unsigned int w);
int zig_overflow_flag_mul_u(zu64 a, zu64 b, unsigned int w);
int zig_overflow_flag_shl_s(z64 a, z64 b, unsigned int w);
int zig_overflow_flag_shl_u(zu64 a, zu64 b, unsigned int w);
int zig_overflow_flag_neg_s(z64 a, unsigned int w);
int zig_overflow_flag_neg_u(zu64 a, unsigned int w);

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
   (false-panics on in-range negatives). Defined once in zig_runtime.c
   (external linkage) and only declared here, so the runtime is linked in
   exactly one place for both single-stream and multi-module output.
   Copied from the zig0-oracle header (src/include/zig_runtime.h:96-185),
   message standardized to "integer cast overflow in @intCast". */
typedef char c_char;
usize __bootstrap_usize_from_i64(i64 x);
i32 __bootstrap_i32_from_u32(u32 x);
u32 __bootstrap_u32_from_u64(u64 x);
usize __bootstrap_usize_from_u64(u64 x);
u32 __bootstrap_u32_from_i32(i32 x);
usize __bootstrap_usize_from_i32(i32 x);
i32 __bootstrap_i32_from_usize(usize x);
u8 __bootstrap_u8_from_usize(usize x);
u8 __bootstrap_u8_from_bool(bool b);
f32 __bootstrap_f32_from_f64(double x);
i32 __bootstrap_i32_from_u8(u8 x);
u8 __bootstrap_u8_from_i32(i32 x);
u8 __bootstrap_u8_from_u32(u32 x);
u16 __bootstrap_u16_from_i32(i32 x);
u32 __bootstrap_u32_from_i64(i64 x);
u64 __bootstrap_u64_from_i64(i64 x);
i8 __bootstrap_i8_from_i32(i32 x);
i16 __bootstrap_i16_from_i32(i32 x);
i32 __bootstrap_i32_from_i64(i64 x);
c_char __bootstrap_c_char_from_u8(u8 x);

/* -fsafe checked @intCast helpers (A18). The `int_cast_checked` LIR op carries
   src/dst signedness and widths, so the emitter only maps to these calls; the
   helper recovers the source value from (src_width, src_signed) and bound-checks
   it against the target width/sign. Defined once in zig_runtime.c (external
   linkage) and only declared here; emitted under -fsafe only, so -ffast
   output is byte-unchanged. Covers fixed-width and arbitrary `iN/uN`
   targets and the equal-width sign-change cases. */
z64 zig_cast_checked_s(zu64 v, unsigned int sw, unsigned int ss, unsigned int dw);
zu64 zig_cast_checked_u(zu64 v, unsigned int sw, unsigned int ss, unsigned int dw);

#endif
