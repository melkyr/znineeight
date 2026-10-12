const std = @import("std");
const util = @import("util.zig");

pub fn main() void {
    var r = util.parse_int() catch {
        std.io.printInt(1);
        return;
    };
    std.io.printInt(r);
}
