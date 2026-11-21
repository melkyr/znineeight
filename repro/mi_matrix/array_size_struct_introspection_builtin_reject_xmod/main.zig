// array_size_struct_introspection_builtin_reject_xmod — Task 11H negative
// control: non-integer builtins in an array-size position stay a clean
// `error[3050]`, consistent with `[true]`/`[4.0]`.
//
// `@isWindows()` yields a bool and `@intToFloat`/`@floatCast` yield floats;
// the array-size evaluator's integer whitelist rejects them, so the
// array-size fallback emits the documented hard error.
// Contract: dump rc=2, 0 `.c`,
//   error[3050]: array size is not a constant expression.
var g_bool: [@isWindows()]u8 = undefined;
var g_float: [@intToFloat(f64, 4)]u8 = undefined;

pub fn main() void {
    _ = g_bool;
    _ = g_float;
}
