fn f() void {
    var X = switch (1) { 0 => @as(i32, 1), else => @as(i32, 7) };
    X = X;
}

pub fn main() void {
    f();
}
