const std = @import("std");

const V = union(enum) {
    int: i64,
    bytes: []const u8,
    flag: bool,
};

pub fn main() void {
    var v: V = V{ .int = 3 };
    switch (v) {
        .int => |x| {
            std.io.printInt(@intCast(i32, x));
        },
        .bytes => |b| {
            _ = b;
            std.io.printInt(0);
        },
        .flag => |f| {
            _ = f;
            std.io.printInt(0);
        },
        else => {},
    }
    std.io.writeByte('\n');
}
