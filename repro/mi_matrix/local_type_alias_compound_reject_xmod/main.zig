// local_type_alias_compound_reject_xmod — Task B2 final fix wave negative
// control: a function-local binding whose initializer is a COMPOUND type
// expression naming a local type (`*E`, `E!i32`, `[2]E`, `?E`) is a `type`
// value. Z98 does not model function-local `type` values, so these clean-reject
// instead of leaking `TYPE_TYPE` into lowering and emitting uncompilable C
// (`unknown type name 'zT_5127F14D_type'`).
//
// Before the fix only the bare alias (`const F = E;`) was guarded; the compound
// forms fell through `semanticAnalyzerResolveExpr`'s ptr/array/optional/
// error-union arms, which returned `TYPE_TYPE`, and `lower.zig` lowered the
// binding as a runtime local of `TYPE_TYPE`.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3000]: local type aliases are not supported; bind the container
//   declaration directly
fn ptrAlias() void {
    const E = enum(u8) { A = 1, B };
    const P = *E;
    _ = P;
}

fn euAlias() void {
    const E = enum(u8) { A = 1, B };
    const Q = E!i32;
    _ = Q;
}

fn arrAlias() void {
    const E = enum(u8) { A = 1, B };
    const R = [2]E;
    _ = R;
}

fn optAlias() void {
    const E = enum(u8) { A = 1, B };
    const S = ?E;
    _ = S;
}

pub fn main() void {
    ptrAlias();
    euAlias();
    arrAlias();
    optAlias();
}
