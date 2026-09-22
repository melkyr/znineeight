// undef_ident_cond_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as an IF and WHILE condition. Before the fix
// each resolved silently to `TYPE_VOID`, compiled rc=0, and emitted
// `zT_0 = nope;` (gcc: `zT_0`/`nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:10:8 and
// main.zig:13:11 (one per occurrence).
pub fn main() void {
    if (nope) {
        @panic("if");
    }
    while (nope) {
        @panic("while");
    }
}
