const Foo = struct { x: i32, y: i32 };

pub fn makeBar() Foo {
    var b = Foo{ .x = 10, .y = 20 };
    return b;
}
