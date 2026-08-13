const std = @import("std.zig");
const lib_mod = @import("lib.zig");

fn kindName(s: lib_mod.Shape) i32 {
    if (s == lib_mod.Shape.Circle) {
        return @intCast(i32, 1);
    }
    return @intCast(i32, 0);
}

pub fn main() void {
    var c = lib_mod.Shape{ .Circle = @intCast(i32, 5) };
    std.io.printInt(kindName(c));
}
