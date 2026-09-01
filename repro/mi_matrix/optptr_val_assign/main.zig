extern fn getp() *i32; pub fn main() void { var x: ?*i32 = getp(); x = getp(); _ = x; }
