// comptime_constfold_reject_xmod — Task 5 exact array-size / enum-initializer
// fold reject control.
//
// Pins the clean rejection of shapes the OLD type-resolver evaluators got
// wrong:
//   * `enum { A = 18446744073709551615 + 1 }` — the old i64 evaluator WRAPPED
//     the add (`2^64` -> 0) and the enum compiled SILENTLY with tag 0
//     (official Zig rejects: `value assigned to enum tag with inferred tag
//     type`); the exact fold now declines (outside `[i64 min, u64 max]`) and
//     the enum walk emits `error[3055]`.
//   * `enum(u64) { A = 18446744073709551615 * 2 }` — `2^65 - 2` wrapped to
//     `2^64 - 2` and was accepted silently; now `error[3055]` (Zig rejects).
//   * `var a: [@intCast(u64, 0 - 1)]u8` — the array-size `@intCast` operand now
//     folds to the exact `-1`, fails the exact u64 fit, and emits the preserved
//     `error[3000]` (`@intCast value does not fit the target type`) plus the
//     array-size fallback `error[3050]`.
//   * `var b: [1 << 40]u8` — an exact size above the `0..0xFFFFFFFE` array
//     length bound is unfoldable (`error[3050]`). Z98's array length field is
//     u32, so this is a pre-existing documented bound (Task 1 §9.3), not a
//     Zig claim (Zig 0.15.2 accepts a `2^40`-byte array type at compile time).
//
// Contract: dump rc=2, 0 `.c`, `error[3055]` for the enum sites,
// `error[3000]` + `error[3050]` for the cast-size site and `error[3050]` for
// the over-u32 size. The canonical classifier buckets this as FAIL (a clean
// non-error[3000]-only reject).
const E1 = enum { A = 18446744073709551615 + 1 };
const E2 = enum(u64) { A = 18446744073709551615 * 2 };
var a: [@intCast(u64, 0 - 1)]u8 = undefined;
var b: [1 << 40]u8 = undefined;

pub fn main() void {
    _ = E1.A;
    _ = E2.A;
    _ = a;
    _ = b;
}
