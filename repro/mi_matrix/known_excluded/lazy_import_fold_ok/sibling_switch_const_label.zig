// D3 fix regression probe: a switch case label that is an evaluable NAMED
// constant (`const T = true`), not a `bool_literal`. The deferred import
// resolver already matched the evaluated label, but the semantic analyzer
// matched only `bool_literal`s and therefore typed the `else` module. Both
// now use the same shared selector: the live prong is `constlabel_a.zig`.
//
// GREEN: `constlabel_a ping\nconstlabel_b ping\nswitch const label ok\n`.
const std = @import("std");

const T = true;

const other = @import("constlabel_b.zig");

const impl = switch (1 == 1) {
    T => @import("constlabel_a.zig"),
    else => @import("constlabel_b.zig"),
};

pub fn main() void {
    impl.ping();
    other.ping();
    std.io.write("switch const label ok\n");
}
