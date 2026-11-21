// volatile_add_accept_xmod — GREEN (A10F). Adding the volatile qualifier is
// always allowed (stricter qualification): `*u32 -> *volatile u32` and
// `*[2]u32 -> [*]volatile u32` coerce implicitly with no diagnostic.
//
// RED baseline: `*volatile` does not parse (`error[2000]`).
// GREEN contract: compile/link/run clean, prints "4 8\n".
const std = @import("std");

pub fn main() void {
    var x: u32 = 3;
    const v: *volatile u32 = &x;
    v.* = 4;

    var arr: [2]u32 = [_]u32{ 1, 2 };
    var mv: [*]volatile u32 = &arr;
    mv[1] = 8;

    std.io.printInt(@intCast(i32, x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, arr[1]));
    std.io.writeByte('\n');
}
