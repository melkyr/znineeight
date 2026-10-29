// Off-corpus mutable-for fixture (Task 3 Step 1h): `|*_|` discard capture.
fn fill(s: []u32) void {
    for (s) |*_| {
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
}
