// if_else_null_safe_warn.zig — Task 9h1 fix-round-2 fixture.
//
// `q` is null on the empty then-arm and non-null on the else-arm. The exit
// merge must compare the else assignment against the inherited null state, so
// the post-if dereference is `maybe` and emits exactly one WARN_6002 (not a
// false ERR_2004).
fn if_else_null_safe_warn(c: bool) u32 {
    var x: u32 = 5;
    var q: ?*u32 = null;
    if (c) {
    } else {
        q = &x;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = if_else_null_safe_warn(true);
}
