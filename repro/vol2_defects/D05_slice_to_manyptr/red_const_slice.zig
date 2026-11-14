// D5 sibling shape: const slice -> `[*]const T`.
const std = @import("std");

pub fn main() void {
    const arr = [3]i32{ 10, 20, 30 };
    const sl: []const i32 = arr;
    const mp: [*]const i32 = sl;
    std.io.print("mp[1]={}\n", .{mp[1]});
}
