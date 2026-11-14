// while_guard_exit_null_warn.zig — Task 9h D4h negative fixture.
//
// A `while (p != null)` guard refines the body only. The loop can also exit
// before the first iteration when the guard fails, so `p` is `maybe` after the
// loop and the exit dereference must emit exactly one WARN_6002. The
// dereference inside the guarded body stays clean.
fn while_guard_exit_deref(p: ?*u32) u32 {
    while (p != null) {
        var x: u32 = p.*;
        _ = x;
    }
    return p.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = while_guard_exit_deref(&x);
}
