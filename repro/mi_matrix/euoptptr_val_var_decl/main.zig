extern fn getp() *i32; pub fn main() void { var x: E!?*i32 = @as(?*i32, getp()); _ = x; }
