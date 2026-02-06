fn genericFn(comptime T: type, x: T) T {
    return x;
}

fn anytypeFn(x: anytype) void {
    _ = x;
}

pub fn main() void {
    const a = genericFn(10);
    const b = anytypeFn(3.14);
}
