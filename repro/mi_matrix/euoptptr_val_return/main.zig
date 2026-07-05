const E = error{Bad}; extern fn getp() *i32; fn f() E!?*i32 { return getp(); } pub fn main() void { var r = f(); _ = r; }
