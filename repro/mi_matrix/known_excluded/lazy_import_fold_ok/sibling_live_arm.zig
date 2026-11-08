// D3 sibling probe: live-arm selection. The condition is false, so `exists.zig`
// is the live arm and must load; `missing.zig` is dead and must not.
const std = @import("std");

const impl = if (1 == 2) @import("missing.zig") else @import("exists.zig");

pub fn main() void {
    impl.ping();
    std.io.write("live_arm ok\n");
}
