fn h() E!i32 { return @as(E!i32, @as(i32, 42)); } pub fn main() void { var r: ?E!i32 = @as(?E!i32, h()); _ = r; }
