// while_guard_exit_warn.zig — Task 9h1 null-state foundation fixture.
//
// The loop guard-false exit and the guarded body disagree about `p`, so the
// post-loop dereference is `maybe` and must emit exactly one WARN_6002.
fn while_guard_exit_warn(p: ?*u32) u32 {
    while (p != null) {
        if (p.* != 0) {
            var x: u32 = 1;
            _ = x;
        }
    }
    return p.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = while_guard_exit_warn(&x);
}
