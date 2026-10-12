const std = @import("std");
const lib = @import("lib.zig");
pub fn main() void {
    std.io.printInt(lib.run());
}
