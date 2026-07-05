const E = error{Bad}; pub fn main() void { var x: E!void = error.Bad; _ = x; }
