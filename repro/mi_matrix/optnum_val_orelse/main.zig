fn h() ??u64 { return @as(?u64, @as(u32, 42)); } pub fn main() void { var r: ?u64 = h() orelse @as(u32, 0); _ = r; }
