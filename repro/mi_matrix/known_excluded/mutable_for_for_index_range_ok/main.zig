// Off-corpus mutable-for fixture (Task 3 Step 1j): the `for_index_range`
// wrapper (`for (s, 0..)`) stays legal for a mutable item capture.
fn fill(s: []u32) void {
    for (s, 0..) |*x, i| {
        x.* += 1;
        _ = i;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
}
