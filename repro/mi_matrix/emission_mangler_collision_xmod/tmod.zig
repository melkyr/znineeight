const color = @import("color.zig");

pub const Color = color.Color;

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
