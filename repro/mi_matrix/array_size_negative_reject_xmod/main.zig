// array_size_negative_reject_xmod — Task 4 array-size range-check control.
//
// Before Task 4 the `array_type` arm evaluated a size expression with u32
// WRAPPING arithmetic, so `[0 - 1]u8` folded to `0xFFFFFFFF` and was accepted
// (a `-1` array length); the u32-only `evalConstU32Full` also wrapped. Official
// Zig rejects (`type 'usize' cannot represent integer value '-1'`).
//
// FIX (Task 4, Task 1 §9.3): the size fold is exact for `0..0xFFFFFFFE`
// (`0xFFFFFFFF` stays the unfoldable sentinel) and the `array_type` arm routes
// every size expression through it, so a negative or over-u32 size is
// unfoldable and the existing error[3050] fires.
//
// Contract: dump rc=2, 0 `.c`, `error[3050]: array size is not a constant
// expression` (plus the pre-existing error[2000]-class cascade for the
// undeclared array name; the canonical classifier buckets this as FAIL, which
// is the documented bucket for a non-error[3000] clean reject).
//
// Positive controls that must stay ACCEPTED live in
// `repro/mi_matrix/stdlib_comptime_coerce_typed_slots_xmod` (`[4 * 8]u8`,
// `[10 - 3]u8`).
var a: [0 - 1]u8 = undefined;
var b: [4000000000 + 400000000]u8 = undefined;

pub fn main() void {
    _ = a;
    _ = b;
}
