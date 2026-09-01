const std = @import("std");

pub fn main() void {
    @putChar(@intCast(u8, 'H'));
    @putChar(@intCast(u8, 'i'));
    @stdoutWrite("Hello", 5);
    @stderrWrite("ERR", 3);
    @sleepMs(@intCast(u32, 0));
    std.io.printInt(@intCast(i32, @getChar()));
    @exit(@intCast(u8, 0));
}
