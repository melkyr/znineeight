// builtin_offsetof_xmod — FEATURE-GAP RED fixture (@offsetOf).
// Feature: comptime field byte offset builtin @offsetOf(T, "field").
// RED today: @offsetOf is unrecognized -> clean FAIL diagnostic.
// GREEN (contract): "0 4 8\n" — c:u8@0, b:u32@4 (align4), d:u16@8.
const std = @import("std");

const Mixed = struct {
    c: u8,
    b: u32,
    d: u16,
};

pub fn main() void {
    std.io.printInt(@intCast(i32, @offsetOf(Mixed, "c")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @offsetOf(Mixed, "b")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @offsetOf(Mixed, "d")));
    std.io.writeByte('\n');
}
