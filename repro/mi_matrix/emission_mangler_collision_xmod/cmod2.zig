const Color = @import("tmod.zig").Color;
pub fn kind2() i32 {
    return switch (Color.Blue) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
