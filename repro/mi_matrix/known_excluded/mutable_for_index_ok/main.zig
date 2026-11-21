// Off-corpus mutable-for fixture (Task 3 Step 1e): mutable item plus the
// optional index capture.
fn fill(s: []u32) void {
    for (s) |*x, i| {
        x.* = 1;
        _ = i;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
}
