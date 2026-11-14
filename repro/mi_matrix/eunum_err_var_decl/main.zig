const E = error{Bad}; pub fn main() void { var x: E!u64 = error.Bad; _ = x; }
