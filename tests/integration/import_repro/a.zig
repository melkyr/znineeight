pub const Foo = struct { x: u32 };
pub fn makeFoo(val: u32) Foo {
    return Foo{ .x = val };
}
