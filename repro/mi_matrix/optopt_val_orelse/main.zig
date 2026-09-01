fn h() ??i32 { return null; } pub fn main() void { var r: ?i32 = h() orelse 42; _ = r; }
