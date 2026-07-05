fn g(x: E!?i32) void { _ = x; } pub fn main() void { g(@as(?i32, @as(i32, 42))); }
