const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var em = mod_b.Emitter{ .x = 0 };
    var i = mod_a.makeBinary(20, 1, 2, 3);
    std.io.printInt(@intCast(i32, mod_b.emitInst(&em, i)));
}
