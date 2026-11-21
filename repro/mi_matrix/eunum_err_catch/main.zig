const E = error{Bad}; fn h() E!u64 { return error.Bad; } pub fn main() void { var r: u64 = h() catch 0; _ = r; }
