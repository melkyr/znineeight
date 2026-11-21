// Off-corpus mutable-for fixture (Task 3 Step 1b): `[]const u32` yields a
// `*const u32` capture, so `x.* = 1` is the existing const-assign error[3002].
fn fill(s: []const u32) void {
    for (s) |*x| {
        x.* = 1;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
}
