// np_param_safe.zig — Task 9b NP-1 fixture.
//
// Non-optional pointer-like parameters (`*T`, `[*]T`, `[]T`, fn-ptr) are
// caller-provided, non-null pointers: seed them `safe`. The dereference below
// must report no WARN_6002 (and no other diagnostic).
fn np_param_safe(p: *u32, q: [*]u32, s: []u32, f: fn () void) void {
    if (p.* != 0) {
        var b: u32 = q[0];
        var c: u32 = s[0];
        _ = b;
        _ = c;
    }
    _ = f;
}

pub fn main() void {
    var x: u32 = 0;
    _ = x;
}
