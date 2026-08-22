const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var em = mod_a.Emitter{ .x = 0, .param_count = 2, .return_type = 42 };
    var r = mod_b.emitInst(&em, 1);
    std.io.printInt(@intCast(i32, r));
}
