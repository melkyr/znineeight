// D12 sibling shape: const-discarding slice stored into a struct field.
const std = @import("std");

const Holder = struct { m: []i32 };

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;
    var h: Holder = .{ .m = c };
    h.m[0] = 9;
    std.io.print("m0={}\n", .{h.m[0]});
}
