// D6 cross-module helper: float tagged union type.
pub const ShapeF = union(enum) {
    circle: f32,
    empty,
};
