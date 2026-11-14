// D12 control: the allowed direction `[]T` -> `[]const T` is silent and runs.
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const m: []i32 = arr;
    const c: []const i32 = m;
    std.io.print("c0={}\n", .{c[0]});
}
