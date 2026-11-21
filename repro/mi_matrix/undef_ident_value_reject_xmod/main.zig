// undef_ident_value_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as a VAR-DECLARATION initializer. Before the
// fix it resolved to `TYPE_VOID`, compiled rc=0 with only a tolerated
// `warning[3000]` (source void -> target i32), and emitted `zT_1 = nope;`
// (gcc: `nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:11:17
// (the co-occurring `warning[3000]` may also be present).
pub fn main() void {
    var x: i32 = nope;
    _ = x;
}
