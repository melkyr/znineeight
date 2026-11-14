// S1 in-module RED (compiler crash): a tuple-literal `print` call followed by
// a non-tuple variable print call in the same module SIGSEGVs the compiler
// (rc 139). New sibling found during D0 authoring.
const std = @import("std");

fn logVar(v: i32) void {
    std.io.print("var-bare={}\n", v);
}

pub fn main() void {
    std.io.print("tuple={} {}\n", .{ 7, 8 });
    logVar(5);
}
