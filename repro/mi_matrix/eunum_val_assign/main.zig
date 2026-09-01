const E = error{Bad}; pub fn main() void { var x: E!u64 = 0; x = 42; _ = x; }
