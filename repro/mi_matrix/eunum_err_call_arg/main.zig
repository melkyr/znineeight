const E = error{Bad}; fn g(x: E!u64) void { _ = x; } pub fn main() void { g(error.Bad); }
