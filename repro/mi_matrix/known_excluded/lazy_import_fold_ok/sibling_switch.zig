// D3 sibling probe: switch over an evaluator-foldable bool condition.
const std = @import("std");

const impl = switch (1 == 1) {
    true => @import("exists.zig"),
    else => @import("missing.zig"),
};

pub fn main() void {
    impl.ping();
    std.io.write("switch ok\n");
}
