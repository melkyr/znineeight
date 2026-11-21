pub const Inner = struct {
    a: i32,
    b: i32,
};

pub const Outer = struct {
    tag: i32,
    inner: Inner,
};

pub fn build(v: i32) Outer {
    var o: Outer = undefined;
    o.tag = 1;
    o.inner.a = v;
    o.inner.b = v + @intCast(i32, 1);
    return o;
}
