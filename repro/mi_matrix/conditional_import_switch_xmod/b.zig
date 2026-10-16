// b.zig — POSIX-selected module for conditional_import_switch_xmod (§4).
const std = @import("std");

pub fn ping() void {
    std.io.write("b ping\n");
}
