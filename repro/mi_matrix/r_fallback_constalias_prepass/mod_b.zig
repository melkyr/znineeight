const Foo = struct { x: i32, y: i32 };

pub const Bar = Foo;

pub fn makeBar() Bar {
    var b = Bar{ .x = 10, .y = 20 };
    return b;
}
