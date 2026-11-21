// Regression: a comptime-taken terminating `if` inside an explicit labeled
// block must not leak the folded-arm DCE flag past the block/labeled
// sequence. `run(true)` breaks to the label and must reach `return 42`;
// `run(false)` falls through the folded `if (true) return 7`.
const std = @import("std");

fn run(c: bool) i32 {
    outer: {
        if (c) break :outer;
        if (true) return 7;
    }
    return 42;
}

pub fn main() void {
    std.io.printInt(run(true));
    std.io.writeByte('\n');
    std.io.printInt(run(false));
    std.io.writeByte('\n');
}
