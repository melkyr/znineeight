const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const mod_d = @import("mod_d.zig");
const Color = mod_b.Color;
const Shape = mod_b.Shape;

pub fn main() void {
    std.io.printInt(mod_d.cval() + mod_d.sval() + mod_c.kind() + mod_b.name(Color.Blue) + mod_b.sides(Shape.Square));
}
