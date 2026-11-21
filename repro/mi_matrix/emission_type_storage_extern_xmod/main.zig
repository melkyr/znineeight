const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const Color = mod_b.Color;

pub fn main() void {
    std.io.printInt(mod_c.kind() + mod_b.name(Color.Blue));
}
