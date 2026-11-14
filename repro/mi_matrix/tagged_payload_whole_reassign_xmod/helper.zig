// helper.zig — FX16-F S2 positive-control fixture helper module.
pub const Box = struct { w: i32, h: i32 };

pub const U = union(enum) {
    i: i32,
    box: Box,
    n: i32,
};
