// D4 cross-module siblings: tuple values crossing a module boundary are still
// not nameable/accessable; the named-struct grouped return works.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    std.io.print("pair={}\n", .{helper.Pair});
    const d = helper.divmod(17, 5);
    std.io.print("q={} r={}\n", .{ d.q, d.r });
}
