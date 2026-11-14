// enum_init_memberref_reject_xmod — Task 11J negative control: an enum-member
// reference in an initializer is a clean reject.
//
// Official Zig rejects `B = A` / `B = E.A` (`error: dependency loop detected`).
// Enum members are not module symbols, so `evalConstI64Full` returns `null` and
// the post-layout pass emits the dedicated hard error. Before the fix the
// initializer silently became the auto-increment value (6, not the true 5).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
const EIdent = enum(u8) { A = 5, B = A };
const EQual = enum(u8) { A = 5, B = EQual.A };

pub fn main() void {
    _ = EIdent.B;
    _ = EQual.B;
}
