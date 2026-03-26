const Error = error{ Foo };

fn testErrDefer(fail: bool) !void {
    var x: i32 = 0;
    errdefer x = 1;
    if (fail) return Error.Foo;
}

pub fn main() void {
    _ = testErrDefer(true) catch {};
    _ = testErrDefer(false) catch {};
}
