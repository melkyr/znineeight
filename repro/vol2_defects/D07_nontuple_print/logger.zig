// D7 cross-module helper: the non-tuple literal call lives in logger.zig.
const std = @import("std");

pub fn logBare() void {
    std.io.print("helper-bare={}\n", 5);
}
