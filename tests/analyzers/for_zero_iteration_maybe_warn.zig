// for_zero_iteration_maybe_warn.zig — Task 9h1 fix-round fixture.
//
// A `for` may execute zero iterations, so the pre-loop `maybe` state is a real
// exit alongside the body's `q = null`. The exit merge must warn; it must not
// report a false definite-null ERR_2004 from the body assignment alone.
fn for_zero_iteration_maybe_warn(p: ?*u32, n: u32) u32 {
    var q: ?*u32 = p;
    for (0..n) |i| {
        _ = i;
        q = null;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = for_zero_iteration_maybe_warn(&x, 0);
}
