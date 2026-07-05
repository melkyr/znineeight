fn g(x: ?u64) void { _ = x; } pub fn main() void { g(@as(u32, 42)); }
