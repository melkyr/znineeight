// undef_ident_arg_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as a CALL ARGUMENT to a declared function.
// Before the fix the argument resolved silently to `TYPE_VOID`, compiled rc=0,
// and emitted `zT_1 = nope;` (gcc: `zT_1`/`nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:13:9.
fn take(x: i32) void {
    _ = x;
}

pub fn main() void {
    take(nope);
}
