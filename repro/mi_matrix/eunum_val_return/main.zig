const E = error{Bad}; fn f() E!u64 { return 42; } pub fn main() void { var r = f(); _ = r; }
