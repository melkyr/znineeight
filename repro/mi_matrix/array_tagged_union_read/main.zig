const std = @import("std.zig");

const Command = union(enum) {
    Quit: void,
    Go: i32,
};

pub fn main() void {
    var arr: [2]Command = [2]Command{ Command{ .Go = @intCast(i32, 3) }, Command{ .Go = @intCast(i32, 4) } };
    var r: i32 = @intCast(i32, 0);
    switch (arr[0]) {
        .Quit => r = @intCast(i32, 0),
        .Go => |d| r = d,
    }
    switch (arr[1]) {
        .Quit => r = r + @intCast(i32, 0),
        .Go => |d| r = r + d,
    }
    std.io.printInt(r);
}
