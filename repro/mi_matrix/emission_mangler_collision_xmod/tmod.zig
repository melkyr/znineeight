pub const Color = enum(u8) {
    Red,
    Green,
    Blue,
};

pub fn name(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
