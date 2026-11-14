// a.zig — Windows-selected module for conditional_import_*_xmod (§4).
// Selected by `if (@isWindows()) @import("a.zig") else @import("b.zig")`.
const std = @import("std");

pub fn ping() void {
    std.io.write("a ping\n");
}
