// D7 sibling shape: an aliased `print` callee with a non-tuple argument.
const std = @import("std");

pub fn main() void {
    const p = std.io.print;
    p("{}\n", 5);
}
