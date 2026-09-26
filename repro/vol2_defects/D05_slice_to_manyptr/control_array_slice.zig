// D5 control: array -> slice is fine.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 10, 20, 30 };
    const sl: []i32 = arr;
    std.io.print("sl[1]={} len={}\n", .{ sl[1], sl.len });
}
