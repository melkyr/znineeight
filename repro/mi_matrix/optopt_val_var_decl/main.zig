pub fn main() void { var x: ??i32 = @as(?i32, @as(i32, 42)); _ = x; }
