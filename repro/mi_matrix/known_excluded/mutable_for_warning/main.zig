// Off-corpus mutable-for fixture (Task 3 Step 1l): a positive `|*x|` fixture
// with an unrecognized escape -> warning[6] under `--check`; `--check -W` must
// turn that warning into rc=2.
fn fill(s: []u32) void {
    for (s) |*x| {
        x.* = 1;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
    var q: []const u8 = "\q";
    _ = q;
}
