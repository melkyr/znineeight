fn h() E!u64 { return @as(u32, 42); } pub fn main() void { var r: u64 = h() catch 0; _ = r; }
