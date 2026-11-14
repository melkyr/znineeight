const std = @import("std");
const a1 = @import("a1.zig");
pub fn main() void {
    var x = a1.make();
    std.io.printInt(x.v);
}
