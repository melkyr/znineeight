// undef_ident_return_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as a RETURN value. Before the fix the return
// expression resolved silently to `TYPE_VOID`, compiled rc=0, and emitted
// `zT_0 = nope;` (gcc: `nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:9:11.
fn get() i32 {
    return nope;
}

pub fn main() void {
    _ = get();
}
