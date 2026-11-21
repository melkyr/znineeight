const E = error{Bad}; fn f() E!i32 { return error.Bad; } pub fn main() void { var r = f(); _ = r; }
