const std = @import("std");

const V = union(enum) {
    int: i64,
    bytes: []const u8,
    flag: bool,
};

const P = union(enum) {
    int: i64,
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
    var p: P = P{ .int = 7 };
    std.io.print("P=", .{});
    std.io.print("{}\n", .{p});
}
