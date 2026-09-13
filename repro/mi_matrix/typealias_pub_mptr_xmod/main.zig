// typealias_pub_mptr_xmod — RED->GREEN (A9F-a). Cross-module `pub const
// T = [*]u8` used as a local declared type and a param type.
// RED (`7a9a9081`): `'p' undeclared` (silent bad C).
// GREEN: compile/link/run clean, prints 7\n.
// Fix (A9F-a): resolved named type written back to the imported alias symbol.
const lib = @import("mod_b.zig");
const std = @import("std");

pub fn main() void {
    const b = [_]u8{ 7, 8 };
    var p: lib.T = &b;
    std.io.printInt(@intCast(i32, lib.first(p)));
    std.io.writeByte('\n');
}
