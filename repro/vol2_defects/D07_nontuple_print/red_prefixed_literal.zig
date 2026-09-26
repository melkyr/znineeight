// D7 sibling shape: the literal text around the dropped placeholder is kept,
// so `bare={}\n` prints `bare=\n`.
const std = @import("std");

pub fn main() void {
    std.io.print("bare={}\n", 5);
}
