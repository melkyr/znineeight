// builtin_ptr_roundtrip_xmod — FEATURE-GAP RED fixture (@intFromPtr/@ptrFromInt).
// Feature: modern pointer-int aliases @intFromPtr(p) and @ptrFromInt(a).
// RED today (if absent): unknown builtin -> clean FAIL.
// GREEN (contract): "42\n" — round-trip addr -> ptr, store through it.
const std = @import("std");

pub fn main() void {
    var v: i32 = 7;
    var p = &v;
    var a = @intFromPtr(p);
    var q = @ptrFromInt(a);
    q.* = 42;
    std.io.printInt(v);
    std.io.writeByte('\n');
}
