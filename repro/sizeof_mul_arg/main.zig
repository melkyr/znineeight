const S = struct { a: u32, b: u32 };
fn sink(x: usize) void { _ = x; }
pub fn main() void { var count: usize = 3; sink(count * @sizeOf(S)); }
