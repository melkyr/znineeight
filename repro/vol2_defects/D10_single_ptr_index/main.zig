// D10 in-module RED (acceptance bug): the Language Spec says `p[0]` on a
// single-item pointer is strictly rejected, but it compiles and runs.
// The `p.*` deref and many-item pointer `mp[i]` controls work too.
const std = @import("std");

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    std.io.print("p[0]={}\n", .{p[0]});
    std.io.print("p.*={}\n", .{p.*});

    var arr = [3]i32{ 10, 20, 30 };
    const mp: [*]i32 = arr;
    std.io.print("mp[1]={}\n", .{mp[1]});
}
