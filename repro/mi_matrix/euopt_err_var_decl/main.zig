const E = error{Bad}; pub fn main() void { var x: E!?i32 = error.Bad; _ = x; }
