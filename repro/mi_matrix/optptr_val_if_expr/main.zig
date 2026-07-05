extern fn getp() *i32; pub fn main() void { var c: bool = true; var r: ?*i32 = if (c) @as(?*i32, getp()) else @as(?*i32, getp()); _ = r; }
