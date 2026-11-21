fn f() void {
    var X: i32 = switch (1) { 0 => 1, else => 7 };
    X = X;
}

pub fn main() void {
    f();
}
