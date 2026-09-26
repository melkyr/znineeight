// D5 in-module RED: an implicit `[]T` -> `[*]T` coercion compiles (rc 0) but
// emits C that gcc rejects (`cannot convert to a pointer type`).
const std = @import("std");

pub fn main() void {
    var arr = [3]i32{ 10, 20, 30 };
    const sl: []i32 = arr;
    const mp: [*]i32 = sl;
    std.io.print("mp[1]={}\n", .{mp[1]});
}
