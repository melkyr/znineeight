const std = @import("std");
const mod = @import("mod.zig");
const SC = mod.Ctx;
pub fn main() void {
    var c: SC = SC{ .store = undefined, .v = 7 };
    var inst = mod.gblk.insts.items[0];
    std.io.printInt(c.v);
}
