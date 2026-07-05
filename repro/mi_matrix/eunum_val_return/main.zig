fn f() E!u64 { return @as(u32, 42); } pub fn main() void { var r = f(); _ = r; }
