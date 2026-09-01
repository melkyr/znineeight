fn h() ??u64 { return null; } pub fn main() void { var r: ?u64 = h() orelse null; _ = r; }
