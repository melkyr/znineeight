// D3 sibling probe: nested conditional imports, both dead arms missing.
const std = @import("std");

const impl = if (1 == 1) (if (1 == 1) @import("exists.zig") else @import("missing.zig")) else @import("missing.zig");

pub fn main() void {
    impl.ping();
    std.io.write("nested ok\n");
}
