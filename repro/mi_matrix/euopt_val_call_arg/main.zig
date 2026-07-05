const E = error{Bad}; fn g(x: E!?i32) void { _ = x; } pub fn main() void { g(42); }
