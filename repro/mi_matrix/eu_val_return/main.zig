const E = error{Bad}; fn f() E!i32 { return 42; } pub fn main() void { var r = f(); _ = r; }
