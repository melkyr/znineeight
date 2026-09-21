// enum_init_builtin_reject_xmod — Task 11J negative control: non-integer-valued
// builtins in an enum initializer are a clean reject.
//
// `@isWindows()` yields a bool and `@intToFloat`/`@floatCast` yield floats;
// enum tags are integers, so `evalConstI64Full` has no arm for them and the
// post-layout pass emits the dedicated hard error. Before the fix each silently
// became the auto-increment value 0.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
const EBool = enum(u8) { A = @isWindows() };
const EFloat = enum(u8) { A = @intToFloat(f64, 3) };
const ECast = enum(u8) { A = @floatCast(f32, 3.0) };

pub fn main() void {
    _ = EBool.A;
    _ = EFloat.A;
    _ = ECast.A;
}
