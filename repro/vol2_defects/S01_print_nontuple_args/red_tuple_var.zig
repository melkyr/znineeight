// S1 shape: the spec explicitly allows a tuple VARIABLE as the argument
// container ("tuple literal ... or a tuple variable"). Historically rejected
// with error[3013], then FD1's interim error[3065]; FIXED by FD2 -- this file
// is the converted flagship: compile/build/run rc 0, stdout `tuple-var=7 8`
// (Zig 0.15.2 parity). See NOTES.md.
const std = @import("std");

pub fn main() void {
    const t = .{ 7, 8 };
    std.io.print("tuple-var={} {}\n", t);
}
