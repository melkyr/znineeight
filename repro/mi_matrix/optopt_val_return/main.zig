fn f() ??i32 { return @as(?i32, @as(i32, 42)); } pub fn main() void { var r = f(); _ = r; }
