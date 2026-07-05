const E = error{Bad}; pub fn main() void { var c: bool = true; var r: ?E!i32 = if (c) @as(?E!i32, error.Bad) else @as(?E!i32, @as(E!i32, @as(i32, 0))); _ = r; }
