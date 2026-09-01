const E = error{Bad}; fn g(x: E!void) void { _ = x; } pub fn main() void { g(error.Bad); }
