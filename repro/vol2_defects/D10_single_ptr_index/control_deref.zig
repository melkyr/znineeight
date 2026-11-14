// D10 control: deref-only access on the single pointer, and many-item
// indexing.
const std = @import("std");

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    std.io.print("p.*={}\n", .{p.*});

    var arr = [3]i32{ 10, 20, 30 };
    const mp: [*]i32 = arr;
    std.io.print("mp[1]={}\n", .{mp[1]});
}
