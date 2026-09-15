const std = @import("std");

const MyUnion = union(enum) {
    A: i32,
    B: f64,
};

pub fn main() void {
    var u: MyUnion = MyUnion{ .A = @intCast(i32, 10) };
    u.tag = @intCast(u32, 1);
    std.io.printInt(@intCast(i32, 0));
    std.io.writeByte('\n');
}
