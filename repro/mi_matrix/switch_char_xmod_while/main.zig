const std = @import("std.zig");
const lib = @import("lib.zig");
pub fn main() void {
    std.io.printInt(lib.run());
}
