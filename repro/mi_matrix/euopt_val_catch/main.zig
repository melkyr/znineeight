const E = error{Bad}; fn h() E!?i32 { return 42; } pub fn main() void { var r: ?i32 = h() catch null; _ = r; }
