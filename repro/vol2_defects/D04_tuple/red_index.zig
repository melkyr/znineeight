// D4 sibling shape: `t[0]` passes sema (compile rc 0) but emits C that gcc
// rejects (`subscripted value is neither array nor pointer nor vector`).
const std = @import("std");

pub fn main() void {
    const anon = .{ 10, 20 };
    std.io.print("t[0]={} t[1]={}\n", .{ anon[0], anon[1] });
    std.io.print("tuple={}\n", .{anon});
}
