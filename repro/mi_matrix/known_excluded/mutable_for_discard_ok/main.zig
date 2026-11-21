// Off-corpus mutable-for fixture (Task 3 Step 1h; Task 4 e2e): `|*_|` discard
// capture. The discard temp is DCE'd, so only rc + stdout are asserted (the
// buffer stays zero: nothing is written).
const std = @import("std");

fn fill(s: []u32) void {
    for (s) |*_| {
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
