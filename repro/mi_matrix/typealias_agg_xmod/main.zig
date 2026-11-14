// typealias_agg_xmod — GREEN guard (A9F-a). Cross-module `pub` struct/enum
// aliases (`const Point = struct{...}`, `const Color = enum{...}`) used in
// annotation / param / return positions must stay byte-identical.
// Contract: compile-clean, run prints 16\n.
const lib = @import("mod_b.zig");
const std = @import("std");

pub fn main() void {
    var p: lib.Point = lib.Point{ .x = 7, .y = 8 };
    std.io.printInt(lib.sumX(p) + lib.colorInt(lib.Color.Green));
    std.io.writeByte('\n');
}
