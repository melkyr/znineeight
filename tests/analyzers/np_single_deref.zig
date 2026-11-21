// np_single_deref.zig — Task 9b NP-4 fixture.
//
// A single dereference whose source is an optional parameter. Optional
// parameters stay conservative (`maybe`) until a guard refines them, so this is
// one potential null dereference. It must be reported exactly once across all
// passes (null diagnostics belong to the null pass only).
fn np_single_deref(p: ?*u32) void {
    if (p.* != 0) {
        var x: u32 = 1;
        _ = x;
    }
}

pub fn main() void {
    var x: u32 = 0;
    np_single_deref(&x);
}
