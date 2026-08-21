const mod_a = @import("mod_a.zig");

pub const Color = mod_a.Color;

pub fn kind() i32 {
    return switch (Color.Green) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
