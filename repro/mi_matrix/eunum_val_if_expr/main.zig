const E = error{Bad}; pub fn main() void { var c: bool = true; var r: E!u64 = if (c) 42 else 0; _ = r; }
