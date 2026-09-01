const std = @import("std");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var o = lib_mod.build(@intCast(i32, 42));
    std.io.printInt(o.inner.a);
    std.io.printInt(o.inner.b);
}
