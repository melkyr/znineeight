const E = error{Bad}; extern fn getp() *i32; fn h() E!?*i32 { return error.Bad; } pub fn main() void { var r: ?*i32 = h() catch getp(); _ = r; }
