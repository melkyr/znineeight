// switch_order_maybe_warn.zig — Task 9h1 fix-round-2 fixture.
//
// Prong 0 leaves `q` at its inherited null state; the `else` prong writes a
// non-null address. The exit merge must compare that explicit safe state
// against inherited null in either prong order, so the post-switch
// dereference is `maybe` and emits exactly one WARN_6002 (not a false
// ERR_2004).
fn switch_order_maybe_warn(n: u32) u32 {
    var x: u32 = 5;
    var q: ?*u32 = null;
    switch (n) {
        0 => {
        },
        else => {
            q = &x;
        },
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = switch_order_maybe_warn(0);
}
