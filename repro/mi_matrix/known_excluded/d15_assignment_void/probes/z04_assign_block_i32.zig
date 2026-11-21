var g: i32 = 0;
var sink: i32 = 0;
pub fn main() void {
    const y: i32 = blk: { break :blk g = 1; };
    sink = y;
}
