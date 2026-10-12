const E = error{Bad}; pub fn main() void { var x: E!u64 = 0; x = error.Bad; _ = x; }
