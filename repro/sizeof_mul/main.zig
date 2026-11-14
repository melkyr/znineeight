const S = struct { a: u32, b: u32 };
pub fn main() void { var count: usize = 3; var n: usize = count * @sizeOf(S); _ = n; }
