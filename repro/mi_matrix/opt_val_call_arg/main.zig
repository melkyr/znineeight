fn g(x: ?i32) void { _ = x; } pub fn main() void { g(@as(i32, 42)); }
