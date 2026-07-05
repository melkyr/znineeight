fn h() E!?i32 { return @as(?i32, @as(i32, 42)); } pub fn main() void { var r: ?i32 = h() catch null; _ = r; }
