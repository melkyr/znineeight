const E = error{X}; pub fn main() void { var a: E!i32 = 0; var b: i32 = 42; a = b; _ = a; }
