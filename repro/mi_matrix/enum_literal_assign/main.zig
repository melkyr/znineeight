const std = @import("std");

const Mode = union(enum) {
    Idle: void,
    Run: void,
    Stop: void,
};

pub fn main() void {
    var m: Mode = .Idle;
    m = .Run;
    const v = switch (m) {
        .Idle => @intCast(i32, 0),
        .Run => @intCast(i32, 1),
        .Stop => @intCast(i32, 2),
        else => @intCast(i32, 99),
    };
    std.io.printInt(v);
}
