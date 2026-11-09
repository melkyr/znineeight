fn f() void {
    const X = if (true) 1 else 2;
    _ = X;
}

pub fn main() void {
    f();
}
