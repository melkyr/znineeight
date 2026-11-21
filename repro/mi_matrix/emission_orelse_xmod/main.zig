const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var r = mod_b.useReturn("pre", 7);
    var c = mod_b.useContinue("pre", 7);
    var t = r orelse 0;
    std.io.printInt(t + c);
}
