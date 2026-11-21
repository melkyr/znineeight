// D12 sibling shape: const-discarding slice returned from a function.
const std = @import("std");

fn unfreeze(c: []const i32) []i32 {
    return c;
}

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;
    const m = unfreeze(c);
    m[0] = 9;
    std.io.print("m0={}\n", .{m[0]});
}
