extern fn getp() *i32; pub fn main() void { var c: bool = true; var r: ?*i32 = if (c) getp() else getp(); _ = r; }
