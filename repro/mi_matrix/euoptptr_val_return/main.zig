extern fn getp() *i32; fn f() E!?*i32 { return @as(?*i32, getp()); } pub fn main() void { var r = f(); _ = r; }
