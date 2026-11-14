// while_guard_body_ok.zig — Task 9h1 null-state foundation fixture.
//
// A `while (p != null)` guard refines the body, so the in-body dereference is
// safe. There is no post-loop dereference, so the fixture is clean.
fn while_guard_body_ok(p: ?*u32) u32 {
    var r: u32 = 0;
    while (p != null) {
        if (p.* != 0) {
            r = 1;
        }
    }
    return r;
}

pub fn main() void {
    var x: u32 = 1;
    _ = while_guard_body_ok(&x);
}
