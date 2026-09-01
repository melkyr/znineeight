const E = error{Bad}; fn h() ?E!i32 { return 42; } pub fn main() void { var r: E!i32 = h() orelse 0; _ = r; }
