// D5 control: array -> [*]T (mutable and const) works.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 10, 20, 30 };
    const mp: [*]i32 = arr;
    const cmp: [*]const i32 = arr;
    std.io.print("mp[2]={} cmp[0]={}\n", .{ mp[2], cmp[0] });
}
