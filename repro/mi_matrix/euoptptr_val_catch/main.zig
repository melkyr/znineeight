extern fn getp() *i32; fn h() E!?*i32 { return @as(?*i32, getp()); } pub fn main() void { var r: ?*i32 = h() catch @as(?*i32, @as(*i32, @intToPtr(*i32, 0))); _ = r; }
