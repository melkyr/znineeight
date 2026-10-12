pub const Inner = struct {
    a: i32,
    b: i32,
};

pub const Outer = struct {
    tag: i32,
    inner: Inner,
};
