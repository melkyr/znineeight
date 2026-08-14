const std = @import("std");

const Command = union(enum) {
    Quit: void,
    Go: i32,
};

fn maybe(k: i32) ?Command {
    if (k == @intCast(i32, 0)) return null;
    return .{ .Go = k };
}

pub fn main() void {
    var c: Command = maybe(@intCast(i32, 0)) orelse .{ .Go = @intCast(i32, 6) };
    var r: i32 = @intCast(i32, 0);
    switch (c) {
        .Quit => r = @intCast(i32, 0),
        .Go => |d| r = d,
    }
    std.io.printInt(r);
}
