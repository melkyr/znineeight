// enum_init_not_constant_xmod — Task 11J negative control: a non-constant
// explicit enum initializer is a clean reject, never a silent auto-increment.
//
// `foo()` is not comptime-known, so `evalConstI64Full` returns `null` and the
// post-layout re-evaluation pass emits the dedicated hard error. Before the fix
// the initializer silently became the auto-increment value 0.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
fn foo() u8 { return 3; }

const E = enum(u8) { A = foo(), B };

pub fn main() void {
    _ = E.A;
}
