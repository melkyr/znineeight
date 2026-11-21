fn f() void {
    var X = if (true) @as(i32, 1) else @as(i32, 2);
    X = X;
}

pub fn main() void {
    f();
}
