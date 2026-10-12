const std = @import("std");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var w = lib_mod.makeWrapper(@intCast(i64, 42));
    std.io.printInt(@intCast(i32, w.data.Int));
}
