// Off-corpus mutable-for fixture (Task 4 fix round 2): a named mutable
// capture over a single-item pointer (`*u32`) has no resolvable element type
// (sema's element box stays TYPE_UNDEFINED), so it must be rejected with
// error[3078] instead of reaching lowering (where the invariant guard would
// abort). The by-value form `for (p) |x|` is unchanged.
fn fill() void {
    var v: u32 = 1;
    var p: *u32 = &v;
    for (p) |*x| {
        _ = x;
    }
}

pub fn main() void {
    fill();
}
