const E = error{Bad}; pub fn main() void { var x: ?E!i32 = 0; x = null; _ = x; }
