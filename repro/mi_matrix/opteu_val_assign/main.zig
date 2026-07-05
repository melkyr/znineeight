pub fn main() void { var x: ?E!i32 = @as(E!i32, @as(i32, 0)); x = @as(E!i32, @as(i32, 42)); _ = x; }
