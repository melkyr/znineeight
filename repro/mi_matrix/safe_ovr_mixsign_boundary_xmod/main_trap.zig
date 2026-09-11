// safe_ovr_mixsign_boundary_xmod (case A) — A15 mixed-sign overflow boundary.
//
// Companion to main.zig (case B). See that file's header for the full A15 /
// A14-Q4 carrier rationale. This entry pins the OTHER direction of the changed
// mixed-sign boundary:
//
//   A) `i32 0 + u32 4294967295` (declared `i32`)
//      carrier: 0 + 4294967295 = 4294967295, above i32 MAX -> POST `-fsafe`
//      traps (rc 133, empty stdout): the `overflow_flag` predicate is computed
//      on the carrier operands, not on emitter-cast-to-i32 operands.
//      PRE (A6F) cast the u32 operand to i32 (-1), so 0 + (-1) = -1 was in
//      range and printed `-1` (rc 0).
//
// Expected here: `-fsafe` POST rc 133 empty; `-fsafe` PRE rc 0 `-1\n`.
// `-ffast` (both PRE and POST) emits no guard: rc 0, `-1\n`.
const std = @import("std");

pub fn main() void {
    var a1: i32 = 0;
    var a2: u32 = 4294967295;
    var ra: i32 = a1 + a2;
    std.io.printInt(ra);
    std.io.writeByte(10);
}
