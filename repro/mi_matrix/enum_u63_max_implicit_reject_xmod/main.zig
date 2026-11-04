// enum_u63_max_implicit_reject_xmod — an implicit successor after the u63
// maximum (2^63 - 1) does not fit `u63`. The shared member walk stores a
// provisional duplicate maximum for the implicit member and lets the existing
// unsigned-width fit gate own the diagnostic; it must not overflow its own
// successor increment (which previously wrapped to i64 min and produced a
// spurious secondary `error[3062]`).
//
// Contract: rc 2, no `.c`, exactly one `error[3000]` (unsigned enum backing
// width at `B`) and no secondary `error[3062]`.
const E = enum(u63) { A = 9223372036854775807, B };

pub fn main() void {
    _ = E.A;
}
