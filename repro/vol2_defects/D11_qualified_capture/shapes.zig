// D11 cross-module helper: tagged union type and an unqualified-capture
// switch.
pub const Shape = union(enum) {
    circle: f32,
    rect: struct { w: i32, h: i32 },
    empty,
};

pub fn val(s: Shape) f32 {
    return switch (s) {
        .circle => |r| r,
        else => 0,
    };
}
