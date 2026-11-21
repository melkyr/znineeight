// undef_ident_binop_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as a BINARY-OPERAND and as an ASSIGNMENT RHS.
// Before the fix both resolved silently to `TYPE_VOID`, compiled rc=0 with only
// a tolerated `warning[3000]` (source void -> target i32), and emitted
// `zT_1 = nope;` / `zT_3 = nope;` (gcc: `nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:12:8 and
// main.zig:13:17 (the co-occurring `warning[3000]`s may also be present).
pub fn main() void {
    var x: i32 = 0;
    x = nope;
    var y: i32 = nope + 1;
    _ = x;
    _ = y;
}
