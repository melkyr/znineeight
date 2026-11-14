const E = error{X}; pub fn main() void { var a: E!i32 = 0; var b: E!i64 = 0; a = b; _ = a; }
