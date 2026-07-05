pub fn main() void { var x: ?u64 = @as(u32, 0); x = @as(u32, 42); _ = x; }
