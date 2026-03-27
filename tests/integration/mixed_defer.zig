fn testMixed(fail: bool) !void {
    var x: i32 = 0;
    defer x = 10;
    errdefer x = 1;
    if (fail) return error.Foo;
}

pub fn main() void {
    _ = testMixed(true) catch {};
    _ = testMixed(false) catch {};
}
