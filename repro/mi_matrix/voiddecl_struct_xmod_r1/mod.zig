pub const Foo = struct {
    v: u32,
};

pub fn make() Foo {
    var f = Foo{ .v = 42 };
    return f;
}
