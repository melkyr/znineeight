extern fn getp() *i32; fn g(x: ?*i32) void { _ = x; } pub fn main() void { g(getp()); }
