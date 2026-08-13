const std = @import("std.zig");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var o: lib_mod.Outer = undefined;
    o.tag = 1;
    o.inner.a = @intCast(i32, 7);
    o.inner.b = @intCast(i32, 8);
    std.io.printInt(o.inner.a);
    std.io.printInt(o.inner.b);
}
