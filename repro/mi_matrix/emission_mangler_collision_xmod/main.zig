const std = @import("std");
const m1 = @import("cmod1.zig");
const m2 = @import("cmod2.zig");
const Color = @import("tmod.zig").Color;

pub fn main() void {
    std.io.printInt(m1.kind1() + m2.kind2());
}
