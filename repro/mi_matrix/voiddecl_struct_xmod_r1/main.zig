const std = @import("std");
const mod = @import("mod.zig");
pub fn main() void {
    var x = mod.make();
    std.io.printInt(x.v);
}
