const std = @import("std.zig");
const lib = @import("lib.zig");
pub fn main() void {
    var p = lib.findPath();
    if (p == null) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
}
