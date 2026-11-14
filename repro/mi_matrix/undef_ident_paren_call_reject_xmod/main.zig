// undef_ident_paren_call_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier wrapped in PARENTHESES and then called (`(nope)()`).
// This pins that variant S catches the inner `ident_expr` during its ordinary
// resolution (where an earlier call-path variant needed temp-type keying).
//
// DEFECT (before the fix): rc=0, no diagnostic, emitted
// `zT_0 = nope; (void)zT_0();` (gcc: `zT_0`/`nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:12:5.
pub fn main() void {
    (nope)();
}
