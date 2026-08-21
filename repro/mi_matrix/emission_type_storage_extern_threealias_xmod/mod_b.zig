const mod_a = @import("mod_a.zig");

pub const Color = mod_a.Color;
pub const Shape = mod_a.Shape;

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}

pub fn sides(s: Shape) i32 {
    return switch (s) {
        .Circle => 0,
        .Square => 4,
    };
}
