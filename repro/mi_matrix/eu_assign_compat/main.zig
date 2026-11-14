const E = error{X}; fn f() E!i32 { return 0; } pub fn main() void { var x: E!i32 = f(); x = f(); _ = x; }
