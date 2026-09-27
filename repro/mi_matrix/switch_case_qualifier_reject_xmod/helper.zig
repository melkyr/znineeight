// FX4 (Volume II D11 extras) reject-fixture helper: a cross-module tagged
// union and the foreign qualifier type used by the `helper.` xmod rows.
pub const Shape = union(enum) {
    circle: i32,
    empty,
};

pub const Other = union(enum) {
    x: i32,
    y: i32,
};
