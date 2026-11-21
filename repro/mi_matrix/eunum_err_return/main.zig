const E = error{Bad}; fn f() E!u64 { return error.Bad; } pub fn main() void { var r = f(); _ = r; }
