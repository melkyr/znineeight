// typealias_pub_aint_xmod — RED->GREEN (A9F-a review fix). A cross-module
// `pub const T = u7` arbitrary-width alias used from an importing module.
//
// RED baseline (A9F-a fixed point `dcc89404`): the imported arb-int alias has
// `type_id 0`, so `lib.T` does not resolve; the module is not emitted and the
// emitted C references an undeclared type (`gcc: unknown type name ...`) with
// no diagnostic.
// GREEN: `lib.T` resolves to `u7`; compile/link/run clean.
// Fix (A9F-a review): the ident_expr registration branch builds the arb-int
// TypeId and writes it to `sym.type_id` (+ the per-module name cache).
// Contract: compile-clean, run prints 6\n.
const std = @import("std");
const lib = @import("mod_b.zig");

pub fn main() void {
    var a: lib.T = 5;
    std.io.printInt(@intCast(i32, lib.bump(a)));
    std.io.writeByte('\n');
}
