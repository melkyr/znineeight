// Off-corpus mutable-for fixture (Task 3 Step 1j; Task 4 e2e): the
// `for_index_range` wrapper (`for (s, 0..)`) stays legal for a mutable item
// capture. The printed values prove in-place mutation of the caller's buffer.
const std = @import("std");

fn fill(s: []u32) void {
    for (s, 0..) |*x, i| {
        x.* += 1;
        _ = i;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    fill(buf[0..]);
    std.io.printInt(@intCast(i32, buf[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, buf[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, buf[2]));
    std.io.writeByte('\n');
}
