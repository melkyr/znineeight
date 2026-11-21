pub const Inner = union {
    Int: i64,
    Sym: i32,
};

pub const Tag = enum { A, B };

pub const Wrapper = struct {
    tag: Tag,
    data: Inner,
};

pub fn makeWrapper(v: i64) Wrapper {
    return Wrapper{ .tag = Tag.A, .data = Inner{ .Int = v } };
}
