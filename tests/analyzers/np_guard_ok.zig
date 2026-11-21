// np_guard_ok.zig — Task 9b NP-5 fixture.
//
// Guard/capture refinement is preserved: `if (p != null)` and `if (p) |q|`
// make the dereferences safe (no WARN_6002), while the `p == null` branch
// proves null and its dereference is ERR_2004_DEFINITE_NULL_DEREF.
fn np_guard_ok(p: ?*u32) u32 {
    var r: u32 = 0;
    if (p != null) {
        r = p.*;
    }
    if (p) |q| {
        r = q.*;
    }
    if (p == null) {
        r = p.*;
    }
    return r;
}

pub fn main() void {
    var x: u32 = 0;
    _ = np_guard_ok(&x);
}
