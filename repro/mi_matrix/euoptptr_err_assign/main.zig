const E = error{Bad}; pub fn main() void { var x: E!?*i32 = @as(?*i32, @as(*i32, @intToPtr(*i32, 0))); x = error.Bad; _ = x; }
