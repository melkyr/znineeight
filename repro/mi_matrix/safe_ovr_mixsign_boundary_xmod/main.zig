// safe_ovr_mixsign_boundary_xmod — A15 mixed-sign overflow boundary pin.
//
// A15 moved the kind=6 integer-overflow guard out of `c89_emit.zig` into
// backend-neutral LIR ops (`add_with_overflow` value + `overflow_flag`) whose
// math lives in C89 runtime helpers. Per A14 Q4 the new ops CARRY their
// operands in the widened C carrier (`long long` / `unsigned long long`) and
// the helper wraps the carrier result to the op's `result_type` width. For
// mixed-sign operands whose true carrier sum lies outside the declared result
// range, that carrier decision CHANGES the trap boundary relative to A6F's
// emitter-side "cast each operand to the result type, then compare" semantics.
// This is design-sanctioned by A14 Q4 (the emitter must no longer reconstruct
// Zig operand casts); the operator should ratify the boundary pinned here.
//
// The two reproduced boundary cases (declared result `i32`):
//
//   B) `i32 -1 + u32 2147483648`  [THIS FILE]
//      carrier: -1 + 2147483648 = 2147483647, inside i32 -> POST `-fsafe`
//      does NOT trap and prints `2147483647`. PRE (A6F) cast the u32 to i32
//      (INT_MIN), so -1 + INT_MIN underflowed and trapped (rc 133, empty).
//
//   A) `i32 0 + u32 4294967295`   [see main_trap.zig]
//      carrier: 0 + 4294967295 = 4294967295, above i32 MAX -> POST `-fsafe`
//      traps (rc 133, empty). PRE cast the u32 to i32 (-1), so 0 + (-1) = -1
//      was in range and printed `-1`.
//
// Expected here: `-fsafe` POST rc 0, stdout `2147483647\n`; `-fsafe` PRE
// rc 133 empty. `-ffast` (both PRE and POST) emits no guard: rc 0,
// `2147483647\n`.
const std = @import("std");

pub fn main() void {
    var b1: i32 = -1;
    var b2: u32 = 2147483648;
    var rb: i32 = b1 + b2;
    std.io.printInt(rb);
    std.io.writeByte(10);
}
