// while_break_maybe_warn.zig — Task 9h1 null-state foundation fixture.
//
// The `break` leaves the loop while `q` is guarded non-null, while the
// guard-false and normal-body exits are null. The snapshotted break state makes
// the post-loop state `maybe`, so the exit dereference warns; it must not be a
// false ERR_2004.
fn while_break_maybe_warn(p: ?*u32) u32 {
    var q: ?*u32 = p;
    while (q != null) {
        if (q != null) {
            break;
        }
        q = null;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = while_break_maybe_warn(&x);
}
