// D3 sibling probe: and/or compound over an evaluator-foldable comparison.
const std = @import("std");

const impl = if ((1 == 1) and true) @import("exists.zig") else @import("missing.zig");

pub fn main() void {
    impl.ping();
    std.io.write("and_or ok\n");
}
