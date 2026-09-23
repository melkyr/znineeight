// comptime_compare_diverge_reject_xmod — Task 9D fix round 3 (operator ruling
// m1293 (b)): DOCUMENTED BOUNDED DIVERGENCE. The comparison fold declines
// (returns unfoldable) when a comparison operand's signedness cannot be derived
// from a declared type, a literal's own sign / `negate`, or an explicit
// `@intCast`/`@as` target — e.g. an arithmetic expression over a const. A
// no-`else` value `if` on such a condition then rejects `error[3059]`.
//
// Zig 0.15.2 (checked with the /tmp/zig-x86_64-linux-0.15.2 oracle) evaluates
// these at arbitrary precision:
//   * `(umax - 1) > 0`, `0 < (umax - 1)`, `(umax - 1) > zero`,
//     `umax > (0 + 0)`, `(a + 1) == 2` are VALID Zig (accepted); Z98 declines
//     to fold and rejects — the documented divergence.
//   * `(umax - 1) < 0` (Zig: "expected type 'i32', found 'void'") and
//     `(u - 300) < 0` (Zig: "type 'u8' cannot represent integer value '300'")
//     are rejected by Zig too, so Z98's rejection matches the outcome.
//
// Contract: rc=2, 0 emitted `.c`, one `error[3059]` per site (7 total).
const std = @import("std");

fn subGt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if ((umax - 1) > 0) 1;
    return x;
}

fn zeroLtSub() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if (0 < (umax - 1)) 2;
    return x;
}

fn subGtZeroConst() i32 {
    const umax: u64 = 18446744073709551615;
    const zero: u64 = 0;
    var x: i32 = if ((umax - 1) > zero) 3;
    return x;
}

fn gtAddZero() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if (umax > (0 + 0)) 4;
    return x;
}

fn arithEq() i32 {
    const a: i32 = 1;
    var x: i32 = if ((a + 1) == 2) 5;
    return x;
}

fn subLt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if ((umax - 1) < 0) 6;
    return x;
}

fn u8SubLt0() i32 {
    const u: u8 = 200;
    var x: i32 = if ((u - 300) < 0) 7;
    return x;
}

pub fn main() void {
    _ = subGt0();
    _ = zeroLtSub();
    _ = subGtZeroConst();
    _ = gtAddZero();
    _ = arithEq();
    _ = subLt0();
    _ = u8SubLt0();
}
