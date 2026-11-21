// for_zero_nonnull_maybe_warn.zig — Task 9h1 fix-round fixture.
//
// The body makes `q` non-null, but zero iterations leave the pre-loop `maybe`
// state. The exit merge must warn; the old body-only merge silently treated the
// post-loop dereference as safe.
fn for_zero_nonnull_maybe_warn(p: ?*u32, n: u32) u32 {
    var q: ?*u32 = p;
    var x: u32 = 7;
    for (0..n) |i| {
        _ = i;
        q = &x;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = for_zero_nonnull_maybe_warn(&x, 0);
}
