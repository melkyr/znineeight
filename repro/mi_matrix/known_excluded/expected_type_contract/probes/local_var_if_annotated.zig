fn f() void {
    var X: ?i32 = if (true) 1 else null;
    X = X;
}

pub fn main() void {
    f();
}
