extern fn getp() *i32; fn f() ?*i32 { return getp(); } pub fn main() void { var r = f(); _ = r; }
