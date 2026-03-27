fn testNested(fail: bool) !void {
    var x: i32 = 0;
    defer x += 100;
    {
        defer x += 10;
        errdefer x += 1;
        if (fail) return error.Foo;
    }
}

pub fn main() void {
    _ = testNested(true) catch {};
    _ = testNested(false) catch {};
}
