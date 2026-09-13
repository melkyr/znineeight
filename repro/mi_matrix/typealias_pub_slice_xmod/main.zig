// typealias_pub_slice_xmod — RED->GREEN (A9F-a). Cross-module `pub const
// T = []i32` used as a local declared type and a param type.
// RED (`7a9a9081`): `'s' undeclared` / incompatible assignment (silent bad C).
// GREEN: compile/link/run clean, prints 10\n.
// Fix (A9F-a): resolved named type written back to the imported alias symbol.
const lib = @import("mod_b.zig");
const std = @import("std");

pub fn main() void {
    const b = [_]i32{ 10, 20, 30 };
    var s: lib.T = b;
    std.io.printInt(lib.first(s));
    std.io.writeByte('\n');
}
