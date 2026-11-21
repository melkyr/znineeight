// lib.zig — FX16-F tagged-union `.tag` sugar fixture helper module.
pub const Shape = union(enum) {
    Circle: i32,
    Square: f64,
    Empty,
    Line: u32,
};

pub const Alias = Shape;

pub const Color = enum { Red, Green, Blue };
