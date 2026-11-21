// array_size_intcast_range_reject_xmod — Task 11S (a) negative control.
//
// DEFECT (Task 11F regression): `evalConstU32Full`'s `@intCast` arm in an
// array-size position folded only the operand (extra-child 1) and IGNORED the
// target type (extra-child 0), so `var a: [@intCast(u8, 300)]u8` folded to
// length 300 and compiled cleanly (rc=0, 0 diagnostics). Official Zig and the
// Z98 spec reject `@intCast(u8, 300)`: 300 does not fit u8.
//
// FIX (Task 11S): the arm now resolves the target type, folds the operand via
// the U32 evaluator (so a function-local `const N` still resolves), and
// requires `intValueFitsType(env, target, v)`; otherwise it emits
// error[3000] and returns the unfoldable sentinel.
//
// Contract: dump rc=2, 0 `.c`, `error[3000]` — the canonical classifier's
// GREEN clean-reject bucket. (The array-size arm also reports the pre-existing
// error[3050] cascade for the same source; the error[3000] is the primary.)
//
// Positive controls that must stay ACCEPTED live in
// `stdlib_intcast_range_xmod` (in-range narrow target, local-const operand).
var a: [@intCast(u8, 300)]u8 = undefined;
var b: [@intCast(u16, 100000)]u8 = undefined;

pub fn main() void {
    _ = a;
    _ = b;
}
