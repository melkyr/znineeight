// enum_u64_max_implicit_reject_xmod — an implicit successor after the i64
// STORAGE maximum does not fit the shared i64 member slot, even though `u64`
// can declare values up to u64 max. The shared walk clamps the successor to
// i64 max (it cannot represent i64 max + 1); both validators must treat that
// implicit successor at the storage maximum as overflow instead of letting it
// duplicate the previous tag value.
//
// Contract: rc 2, no `.c`, `error[3000]` (from the local validator and the
// module gate; two diagnostics today) and no `error[3062]`.
const E = enum(u64) { A = 9223372036854775807, B };

pub fn main() void {
    _ = E.A;
}
