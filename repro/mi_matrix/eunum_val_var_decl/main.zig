const E = error{Bad}; pub fn main() void { var x: E!u64 = 42; _ = x; }
