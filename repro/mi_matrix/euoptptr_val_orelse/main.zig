extern fn getp() *i32; fn h() ??*i32 { return getp(); } pub fn main() void { var r: ?*i32 = h() orelse getp(); _ = r; }
