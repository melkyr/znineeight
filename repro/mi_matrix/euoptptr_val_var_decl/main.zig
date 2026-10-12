const E = error{Bad}; extern fn getp() *i32; pub fn main() void { var x: E!?*i32 = getp(); _ = x; }
