// labeled_outer_break_maybe_warn.zig — Task 9h1 fix-round fixture.
//
// `break :outer` leaves the outer loop while `q` is non-null; the normal inner
// fall-through then sets `q = null`. The labeled exit must land on the outer
// frame, so the post-loop state is `maybe` (WARN_6002), never a false
// ERR_2004 from the body assignment alone.
fn labeled_outer_break_maybe_warn(p: ?*u32, n: u32) u32 {
    var q: ?*u32 = p;
    var x: u32 = 3;
    outer: while (q != null) {
        for (0..n) |i| {
            _ = i;
            q = &x;
            break :outer;
        }
        q = null;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = labeled_outer_break_maybe_warn(&x, 0);
}
