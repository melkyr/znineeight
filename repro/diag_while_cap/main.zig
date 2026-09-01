pub fn main() void { var c: ?*u8 = null; while (c) |p| { _ = p; c = null; } }
