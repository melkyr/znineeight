fn h() ??i32 { return null; } pub fn main() void { var r: ?i32 = h() orelse null; _ = r; }
