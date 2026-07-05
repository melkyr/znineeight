pub fn main() void { var x: E!?i32 = @as(?i32, null); x = @as(?i32, @as(i32, 42)); _ = x; }
