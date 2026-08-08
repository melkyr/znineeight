extern fn __bootstrap_print_int(n: i32) void;
const lib_mod = @import("lib.zig");

fn kindName(s: lib_mod.Shape) i32 {
    if (s == lib_mod.Shape.Circle) {
        return @intCast(i32, 1);
    }
    return @intCast(i32, 0);
}

pub fn main() void {
    var c = lib_mod.Shape{ .Circle = @intCast(i32, 5) };
    __bootstrap_print_int(kindName(c));
}
