const Color = @import("mod_a.zig").Color;

pub fn kind() i32 {
    return switch (Color.Red) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
