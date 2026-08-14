const std = @import("std");

pub fn main() void {
    std.io.printInt(@intCast(i32, 42));
}
