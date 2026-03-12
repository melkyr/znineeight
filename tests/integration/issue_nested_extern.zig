extern fn foo(x: i32) void;

fn fallible() !i32 {
    return 42;
}

fn test_try() !void {
    foo(try fallible());
}

pub fn main() void {
    _ = test_try() catch {};
}
