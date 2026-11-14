const E = error{Bad}; extern fn getp() *i32; fn h() E!?*i32 { return getp(); } pub fn main() void { var r: ?*i32 = h() catch @intToPtr(*i32, 0); _ = r; }
