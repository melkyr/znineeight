const mod_a = @import("mod_a.zig");

pub const Color = mod_a.Color;

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
