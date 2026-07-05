pub fn main() void { var c: bool = true; var r: E!u64 = if (c) @as(E!u64, @as(u32, 42)) else @as(E!u64, @as(u32, 0)); _ = r; }
