pub fn main() void { var c: bool = true; var r: ?E!i32 = if (c) null else @as(?E!i32, @as(E!i32, @as(i32, 0))); _ = r; }
