const E = error{Bad}; fn h() E!i32 { return error.Bad; } pub fn main() void { var r: ?i32 = h() catch 0; _ = r; }
