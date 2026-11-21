// enum_i64_max_implicit_reject_xmod — an implicit successor after the i64
// maximum does not fit `i64`. The shared member walk stores a provisional
// duplicate maximum for the implicit member and lets the existing signed-range
// fit gate own the diagnostic; it must not overflow its own successor
// increment, and must not report a spurious duplicate-tag error instead.
//
// Contract: rc 2, no `.c`, `error[3000]` (signed enum backing range at `B`;
// the local validator and the module gate each report it, so two diagnostics
// appear today) and no secondary `error[3062]`.
const E = enum(i64) { A = 9223372036854775807, B };

pub fn main() void {
    _ = E.A;
}
