// switch_break_maybe_warn.zig — Task 9h1 null-state foundation fixture.
//
// One switch prong breaks out of the loop while `q` is guarded non-null; the
// other prong and the normal prong fall-through are null. The snapshotted
// break state and the switch exit merge must produce `maybe`, so the post-loop
// dereference emits exactly one WARN_6002 (not a false ERR_2004).
fn switch_break_maybe_warn(p: ?*u32, n: u32) u32 {
    var q: ?*u32 = p;
    while (q != null) {
        switch (n) {
            0 => {
                break;
            },
            else => {
                q = null;
            },
        }
        q = null;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = switch_break_maybe_warn(&x, 0);
}
