const std = @import("std");

const Big = union(enum) {
    a: void,
    b: [36]u8,
};

pub fn main() void {
    var u: Big = .a;
    const v = switch (u) {
        .a => @intCast(i32, 0),
        .b => @intCast(i32, 1),
        else => @intCast(i32, 99),
    };
    std.io.printInt(v);
}
