// undef_ident_call_of_call_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as the CALLEE OF A CALLED RESULT (`nope()()`).
// Before the fix the inner ident resolved silently to `TYPE_VOID`, compiled
// rc=0, and emitted `zT_0 = nope; zT_1 = zT_0(); (void)zT_1();` (gcc:
// `zT_0`/`nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:10:4.
pub fn main() void {
    nope()();
}
