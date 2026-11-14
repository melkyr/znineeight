// stdlib_intcast_widen_sign_runtime_xmod — Task B3 item 1: restore the A18
// runtime widening-sign-change `@intCast` trap coverage.
//
// BACKGROUND. The original runtime pin for this shape,
// `repro/mi_matrix/safe_intcast_widen_sign_xmod/main.zig`, was
// `@intCast(u16, @as(i8, -1))`. Task 11U made `@as` fold at comptime, so that
// program became a comptime OUT-OF-RANGE cast (a clean `error[3000]` reject,
// official-Zig-correct) and the runtime trap was no longer exercised. This
// fixture restores the runtime coverage with a genuinely runtime-valued operand
// so the A18 predicate (`src_signed && !dst_signed && src_bits < dst_bits`,
// `i8 -> u16`) routes through `int_cast_checked` (`zig_cast_checked_u`).
//
// CONTRACT.
//   - `-fsafe` (the default): the runtime check traps before any stdout is
//     written — empty stdout, rc 133 (SIGTRAP), `panic: integer cast overflow
//     in @intCast` on stderr.
//   - `-ffast`: the unchecked C cast keeps the wrapped value `65535` (rc 0).
// The runtime gate (`scripts/stdlib/run_fixtures.sh`) runs fixtures under
// `-ffast`, so its committed golden below is `65535` / rc 0; the `-fsafe` trap
// is reproduced by the standalone `repro/intcast_widen_sign_runtime.z98`.
//
//   -ffast golden: "65535\n", rc 0.
const std = @import("std");

// A non-inlined helper with a runtime parameter keeps the cast operand
// runtime-valued (never comptime-folded).
fn widenSign(x: i8) u16 {
    return @intCast(u16, x);
}

pub fn main() void {
    var x: i8 = -1;
    var w: u16 = widenSign(x);
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte(10);
}
