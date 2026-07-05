extern const E = error{Bad}; fn getp() *i32; pub fn main() void { var x: E!?*i32 = getp(); _ = x; }
