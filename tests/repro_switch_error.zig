fn foo(cond: bool) !i32 {
    return switch (cond) {
        true => 42,
        false => error.Bad,
        else => unreachable,
    };
}

pub fn main() void {
    _ = foo(true) catch 0;
}
