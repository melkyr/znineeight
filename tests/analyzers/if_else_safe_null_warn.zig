// if_else_safe_null_warn.zig — Task 9h1 fix-round-2 fixture.
//
// The mirror of `if_else_null_safe_warn`: `q` is non-null on the empty then-arm
// and null on the else-arm. The exit merge must compare the else assignment
// against the inherited safe state, so the post-if dereference is `maybe` and
// emits exactly one WARN_6002 instead of staying silently safe.
fn if_else_safe_null_warn(c: bool) u32 {
    var x: u32 = 5;
    var q: ?*u32 = &x;
    if (c) {
    } else {
        q = null;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = if_else_safe_null_warn(true);
}
