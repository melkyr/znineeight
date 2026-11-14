const std = @import("std");
const lib = @import("lib.zig");
pub fn main() void {
    std.io.printInt(@intCast(i32, lib.classify('a')));
    std.io.printInt(@intCast(i32, lib.classify('q')));
}
