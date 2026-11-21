// np_cond.zig — T9a mode-gating fixture (audit L2 / NP-4).
//
// One dereference (`p.*`) in an `if` condition. Before T9a the null analyzer
// re-runs from every pass: null-only 1, lifetime-only 1, double-free-only 1,
// all passes 3. After T9a the null diagnostics belong to the null pass only,
// so the all-pass run must report exactly one WARN_6002. The parameter is
// optional, so Task 9b keeps it conservative (`maybe`) rather than seeding it
// `safe`; the single-deref mode-gating contract is unchanged.
fn np_cond(p: ?*u32) void {
    if (p.* != 0) {
        var x: u32 = 1;
        _ = x;
    }
}

pub fn main() void {
    var x: u32 = 0;
    np_cond(&x);
}
