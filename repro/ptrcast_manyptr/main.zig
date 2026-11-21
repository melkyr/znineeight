pub fn main() void { var buf: [4]u8 = undefined; var q: [*]u8 = &buf; var p: [*]*u8 = @ptrCast([*]*u8, q); _ = p; }
