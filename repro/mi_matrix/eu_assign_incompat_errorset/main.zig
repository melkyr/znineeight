const E = error{X}; const F = error{X,Y}; pub fn main() void { var a: E!i32 = 0; var b: F!i32 = 0; a = b; _ = a; }
