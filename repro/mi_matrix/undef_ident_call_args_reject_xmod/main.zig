// undef_ident_call_args_reject_xmod — Task 6F regression fixture (variant S).
//
// Same defect as `undef_ident_call_reject_xmod`, but the undeclared callee is
// invoked WITH arguments. The identifier is diagnosed during callee resolution
// (before arguments are checked), so the argument count is irrelevant.
//
// DEFECT (before the fix): rc=0, no diagnostic, emitted
// `zT_0 = nope; zT_0(zT_1, zT_2)` (gcc: `zT_0`/`nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:12:4.
pub fn main() void {
    nope(1, 2);
}
