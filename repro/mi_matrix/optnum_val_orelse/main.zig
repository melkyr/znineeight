fn h() ??u64 { return 42; } pub fn main() void { var r: ?u64 = h() orelse 0; _ = r; }
