fn testOptional() ?i32 {
    const x: ?i32 = 42;
    return x;
}

fn testNestedOptional() ??i32 {
    const x: ??i32 = 42;
    return x;
}

fn testErrorUnion() !i32 {
    const x: !i32 = 42;
    return x;
}

fn testOptionalVoid() ?void {
    const x: ?void = {};
    return x;
}

fn testErrorUnionVoid() !void {
    const x: !void = {};
    return x;
}

fn testNullToOptional() ?i32 {
    const x: ?i32 = null;
    return x;
}

pub fn main() void {
    _ = testOptional();
    _ = testNestedOptional();
    _ = testErrorUnion() catch 0;
    _ = testOptionalVoid();
    _ = testErrorUnionVoid() catch {};
    _ = testNullToOptional();
}
