const E = error{Bad}; pub fn main() void { var r: E!i32 = (null) orelse 42; _ = r; }
