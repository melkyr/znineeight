const Color = @import("mod_a.zig").Color;
const Shape = @import("mod_a.zig").Shape;
const C = Color;
const S = Shape;

pub fn cval() i32 {
    return switch (C.Blue) {
        .Red => 1,
        .Green => 2,
        .Blue => 3,
    };
}

pub fn sval() i32 {
    return switch (S.Square) {
        .Circle => 1,
        .Square => 2,
    };
}
