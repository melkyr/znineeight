// comptime_compare_reject_xmod — Task 3 (signedness-free comparisons):
// over-acceptance shapes stay rejected, matching official Zig 0.15.2.
//
// The exact magnitude+sign comparison makes arithmetic-derived conditions fold
// like Zig's `comptime_int` — but only where Zig accepts. These shapes are
// rejected by Zig too, so Z98 must reject them (Task 9D fix-round-3
// over-acceptance family, now closed):
//
//   * `umax < 0` (u64 const) — Zig: `expected type 'i32', found 'void'`; the
//     condition folds FALSE, so the no-`else` value `if` is invalid;
//   * `(umax - 1) < 0` — same Zig outcome;
//   * `(u - 300) < 0` (u8 const) — Zig: `type 'u8' cannot represent integer
//     value '300'`; the arithmetic peer-fit rule (Task 1 §5.4) declines the
//     `u - 300` fold, so the comparison does not fold;
//   * `(0 - umax) < 0` — Zig: `overflow of integer type 'u64' with value
//     '-18446744073709551615'`; the exact result does not fit the u64 peer, so
//     the fold declines;
//   * `(u + 1000) < 0` (u8 const) — Zig: `type 'u8' cannot represent integer
//     value '1000'`; the untyped operand does not fit the u8 peer;
//   * `((u - 1) - 300) < 0` (u8 const) — the peer-type derivation recurses
//     into the inner `(u - 1)` (sema type u8), so the outer `- 300` declines;
//     Zig: `type 'u8' cannot represent integer value '300'`. Without the
//     recursion the fold computed -101 and silently accepted a program whose
//     runtime arithmetic wraps;
//   * `-umax < 0` (u64 const, fix round 1) — Zig: `negation of type 'u64'`.
//     The unary fold now applies the same peer fit as the binops (sema types
//     `-x` as x's type), so the negative exact result declines;
//   * `(c + 300) == 500` with `const c = @as(u8, 200)` (fix round 1) — Zig:
//     `type 'u8' cannot represent integer value '300'`. The operand-type mirror
//     now recurses into an UNANNOTATED const's initializer, so `c` is typed
//     u8 and the untyped 300 declines;
//   * `MUMAX < 0` at module scope — same as the first shape.
//
// Contract: rc=2, 0 emitted `.c`, one `error[3059]` per site (9 total).
const std = @import("std");

const MUMAX: u64 = 18446744073709551615;

fn u64Lt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if (umax < 0) 1;
    return x;
}

fn subLt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if ((umax - 1) < 0) 2;
    return x;
}

fn u8SubLt0() i32 {
    const u: u8 = 200;
    var x: i32 = if ((u - 300) < 0) 3;
    return x;
}

fn zeroSubUmaxLt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if ((0 - umax) < 0) 4;
    return x;
}

fn u8AddBigLt0() i32 {
    const u: u8 = 200;
    var x: i32 = if ((u + 1000) < 0) 5;
    return x;
}

fn nestedU8SubLt0() i32 {
    const u: u8 = 200;
    var x: i32 = if (((u - 1) - 300) < 0) 7;
    return x;
}

fn modU64Lt0() i32 {
    var x: i32 = if (MUMAX < 0) 6;
    return x;
}

// Fix round 1 (Important): unary `-` escaped the peer-fit rule; sema types
// `-x` as x's type, so `-umax` on a u64 declines (Zig: negation of type 'u64').
fn negUmaxLt0() i32 {
    const umax: u64 = 18446744073709551615;
    var x: i32 = if (-umax < 0) 8;
    return x;
}

// Fix round 1 (Important): an UNANNOTATED const's initializer types the name
// (sema: `c` is u8 via the @as); the operand-type mirror now recurses into the
// init, so `c + 300` declines (Zig: type 'u8' cannot represent 300).
fn unannotatedConstAddLt0() i32 {
    const c = @as(u8, 200);
    var x: i32 = if ((c + 300) == 500) 9;
    return x;
}

pub fn main() void {
    _ = u64Lt0();
    _ = subLt0();
    _ = u8SubLt0();
    _ = zeroSubUmaxLt0();
    _ = u8AddBigLt0();
    _ = nestedU8SubLt0();
    _ = modU64Lt0();
    _ = negUmaxLt0();
    _ = unannotatedConstAddLt0();
}
