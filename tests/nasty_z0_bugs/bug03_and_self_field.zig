pub const Inner = struct {
    value: i32,
};

pub const Outer = struct {
    inner: Inner,
};

pub fn main() void {
    var o = Outer{ .inner = Inner{ .value = 42 } };
    var p = &o;
    // &p.inner fails: zig0 cannot emit &(p->inner)
    var ptr = &p.inner;
    _ = ptr;
}
