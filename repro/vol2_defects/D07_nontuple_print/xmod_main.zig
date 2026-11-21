// D7 cross-module RED: the helper's non-tuple print is a silent no-op.
const std = @import("std");
const logger = @import("logger.zig");

pub fn main() void {
    logger.logBare();
}
