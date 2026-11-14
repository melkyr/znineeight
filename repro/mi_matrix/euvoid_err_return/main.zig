const E = error{Bad}; fn f() E!void { return error.Bad; } pub fn main() void { var r = f(); _ = r; }
