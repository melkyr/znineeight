// if_guard_exit_warn.zig — Task 9h1 null-state foundation fixture.
//
// The then arm is guarded non-null and the implicit else arm is null. The exit
// merge must disagree to `maybe`, never silently `safe`, so the post-if
// dereference emits exactly one WARN_6002 (not ERR_2004).
fn if_guard_exit_warn(p: ?*u32) u32 {
    if (p != null) {
        if (p.* != 0) {
            var x: u32 = 1;
            _ = x;
        }
    }
    return p.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = if_guard_exit_warn(&x);
}
