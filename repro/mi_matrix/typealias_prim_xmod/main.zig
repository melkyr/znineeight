// typealias_prim_xmod — GREEN guard (A9F-a). A cross-module `pub` primitive
// alias (`const Num = i32`) used in annotation / param / return positions must
// keep working byte-for-byte (the working-path pin from A9I Q4).
// Contract: compile-clean, run prints 42\n.
const mod_b = @import("mod_b.zig");
const std = @import("std");

const N = mod_b.Num;

const Holder = struct { v: N };

pub fn main() void {
    var h = Holder{ .v = mod_b.twice(21) };
    std.io.printInt(h.v);
    std.io.writeByte('\n');
}
