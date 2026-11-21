var arr: [2]i32 = .{ 0, 0 };
var sink: i32 = 0;
pub fn main() void {
    const y: i32 = arr[0] = 2;
    sink = y;
}
