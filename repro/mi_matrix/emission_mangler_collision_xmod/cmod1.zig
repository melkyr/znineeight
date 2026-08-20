const tmod = @import("tmod.zig");
const Color = @import("color.zig").Color;
pub fn kind1() i32 {
    return switch (Color.Red) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}
