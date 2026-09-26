// FF (D6/D9) cross-module helper: the f32 tagged union whose literal-payload
// init must narrow at the payload site (same lowering path as in-module), plus
// a union type kept for the layout rows.
pub const ShapeF = union(enum) {
    circle: f32,
    empty,
};

pub const HU = union {
    i: i32,
    u: u32,
};
