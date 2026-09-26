// D5 control: slice -> slice copy is fine.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 10, 20, 30 };
    const a: []i32 = arr;
    const b: []i32 = a;
    std.io.print("b[1]={}\n", .{b[1]});
}
