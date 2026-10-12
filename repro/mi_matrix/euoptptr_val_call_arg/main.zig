const E = error{Bad}; extern fn getp() *i32; fn g(x: E!?*i32) void { _ = x; } pub fn main() void { g(getp()); }
