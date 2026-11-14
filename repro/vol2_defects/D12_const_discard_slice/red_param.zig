// D12 sibling shape: const-discarding slice passed as a function argument.
const std = @import("std");

fn take(m: []i32) void {
    m[0] = 9;
}

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;
    take(c);
    std.io.print("m0={}\n", .{arr[0]});
}
