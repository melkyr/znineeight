const std = @import("std");
const mod_a = @import("mod_a.zig");

pub fn collide(seed: u32) u32 {
    var rt: ?u32 = mod_a.maybeVal(seed);
    var res: ?u32 = mod_a.maybeVal(seed);
    var rtype: u32 = if (res) |rt| rt else 7;
    return rtype;
}

pub fn run() void {
    var v = collide(1);
    std.io.printInt(@intCast(i32, v));
}
