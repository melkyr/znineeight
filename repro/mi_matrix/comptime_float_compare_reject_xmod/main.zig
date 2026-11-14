// comptime_float_compare_reject_xmod — Task 9 fix round 1 (review Critical):
// float comparisons with an INEXACT multi-limb integer operand stay rejected,
// matching official Zig 0.15.2.
//
// The original `ciSignificantBits` counted only the top limb's bits, so a
// multi-limb magnitude reported a tiny significant-bit count and the fold
// fired with an f64-rounded value: `((1 << 64) + 1)` was treated as exactly
// representable and `== 18446744073709551616.0` folded TRUE although the exact
// value differs from 2^64. Zig rejects the no-`else` value `if` (the condition
// is comptime-false) and the pre-Task-9 compiler rejected it with
// `error[3059]`. The corrected `ciSignificantBits` computes
// bitlen(magnitude) - trailing_zeros (65 / 54 for `2^64 + 1`, `2^53 + 1`), so
// the int operand no longer fits the 53-bit peer and the fold declines.
//
// Each site is a comptime-FALSE float comparison in a no-`else` value `if`,
// so Z98 must reject every one with `error[3059]` (rc 2, 0 `.c`) exactly like
// official Zig 0.15.2 (`expected type 'i32', found 'void'`):
//
//   * `((1 << 64) + 1) == 18446744073709551616.0` — exact 2^64 + 1 != 2^64;
//   * `((1 << 64) + 1) <= 18446744073709551616.0` — exact 2^64 + 1 > 2^64;
//   * `((1 << 53) + 1) == 9007199254740992.0`     — exact 2^53 + 1 != 2^53.
//
// RED (f342794a, the buggy helper): all three folded TRUE (the rounded f64
// value was compared), so the program was ACCEPTED and classified OK — an
// over-acceptance that survived the whole battery. GREEN (fix round 1):
// `error[3059]` rc 2 for every site, as pinned by `expected.rc`.
//
// Oracle: official Zig 0.15.2 rejects all three shapes
// (`/tmp/task9/fix/probe/za.zig` is the first with `expected type 'i32',
// found 'void'`; the `<=` and `2^53 + 1` shapes were checked with
// `/tmp/task9/fix/probe/zr*.zig`).
pub fn main() void {
    var x1: i32 = if (((1 << 64) + 1) == 18446744073709551616.0) 1;
    var x2: i32 = if (((1 << 64) + 1) <= 18446744073709551616.0) 2;
    var x3: i32 = if (((1 << 53) + 1) == 9007199254740992.0) 3;
    _ = x1;
    _ = x2;
    _ = x3;
}
