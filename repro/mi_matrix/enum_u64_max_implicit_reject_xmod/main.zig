// enum_u64_max_implicit_reject_xmod — an implicit successor after the u64
// maximum does not fit `u64`. The shared walk computes the raw 64-bit
// successor; both validators must treat the wrap past u64 max as overflow
// instead of letting it duplicate the previous tag value.
//
// Contract: rc 2, no `.c`, `error[3000]` (from the local validator and the
// module gate; two diagnostics today) and no `error[3062]`.
const E = enum(u64) { A = 18446744073709551615, B };

pub fn main() void {
    _ = E.A;
}
