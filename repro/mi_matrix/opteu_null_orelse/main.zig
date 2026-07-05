pub fn main() void { var r: E!i32 = (@as(?E!i32, null)) orelse @as(E!i32, @as(i32, 42)); _ = r; }
