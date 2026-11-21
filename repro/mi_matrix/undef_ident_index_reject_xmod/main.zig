// undef_ident_index_reject_xmod — Task 6F regression fixture (variant S).
//
// An undeclared identifier used as an ARRAY INDEX. Before the fix the index
// expression resolved silently to `TYPE_VOID`, compiled rc=0, and emitted
// `zT_3 = nope;` (gcc: `zT_3`/`nope` undeclared).
//
// EXPECTED (after the fix): dump rc=2, 0 `.c`, `error[20]` at main.zig:10:16.
pub fn main() void {
    var arr: [3]i32 = [3]i32{ 10, 20, 30 };
    var x = arr[nope];
    _ = x;
}
