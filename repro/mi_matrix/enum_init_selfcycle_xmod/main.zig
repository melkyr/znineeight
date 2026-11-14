// enum_init_selfcycle_xmod — Task 11J negative control: a self-referential const
// in an enum initializer terminates as a clean reject, never a hang.
//
// `evalConstI64Full`'s `ident_expr` arm recurses into a const's initializer, so
// `const X = X` recursed forever (observed rc=124, a compiler hang). The
// evaluator now carries a depth cap (16, mirroring `evalConstU32Full`), so the
// cycle terminates as `null` and the post-layout pass emits the dedicated hard
// error.
//
// Contract: dump rc=2, 0 `.c`, NO HANG,
//   error[3055]: enum member value is not a comptime-known integer expression.
const X = X;
const E = enum(u8) { A = X };

pub fn main() void {
    _ = E.A;
}
