// Off-corpus mutable-for fixture (Task 3 Step 1d; Task 4 e2e): a `const`
// BINDING of a mutable slice must not leak binding constness into the pointee
// (`*u32`). The printed values prove in-place mutation of the caller's buffer.
const std = @import("std");

fn fill(s: []u32) void {
    for (s) |*x| {
        x.* = 1;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    const s: []u32 = buf[0..];
    fill(s);
    std.io.printInt(@intCast(i32, buf[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, buf[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, buf[2]));
    std.io.writeByte('\n');
}
