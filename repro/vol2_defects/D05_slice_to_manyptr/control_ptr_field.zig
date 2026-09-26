// D5 control: the explicit `.ptr` workaround works.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 10, 20, 30 };
    const sl: []i32 = arr;
    const mp: [*]i32 = sl.ptr;
    std.io.print("mp[1]={}\n", .{mp[1]});
}
