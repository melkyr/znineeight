fn h() ??i32 { return @as(?i32, null); } pub fn main() void { var r: ?i32 = h() orelse @as(i32, 42); _ = r; }
