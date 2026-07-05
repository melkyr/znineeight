const E = error{Bad}; pub fn main() void { var c: bool = true; var r: E!?*i32 = if (c) error.Bad else @as(E!?*i32, @as(?*i32, @as(*i32, @intToPtr(*i32, 0)))); _ = r; }
