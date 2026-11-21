fn f() void {
    const X: ?i32 = if (true) 1 else null;
    _ = X;
}

pub fn main() void {
    f();
}
