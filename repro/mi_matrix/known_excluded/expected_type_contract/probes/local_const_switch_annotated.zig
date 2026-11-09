fn f() void {
    const X: i32 = switch (1) { 0 => 1, else => 7 };
    _ = X;
}

pub fn main() void {
    f();
}
