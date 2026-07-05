pub fn main() void { var c: bool = true; var r: ?u64 = if (c) @as(?u64, @as(u32, 42)) else @as(?u64, @as(u32, 0)); _ = r; }
