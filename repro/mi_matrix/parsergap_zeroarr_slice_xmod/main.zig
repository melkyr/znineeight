const std = @import("std");

pub fn sourceManagerGetLineOffsets(file_id: u32) []u32 {
    if (file_id == @intCast(u32, 0)) { var dummy: [0]u32 = undefined; return dummy[0..]; }
    var n: [3]u32 = [3]u32{ 1, 2, 3 };
    return n[0..];
}

pub fn main() void {
    var s = sourceManagerGetLineOffsets(0);
    std.io.printInt(@intCast(i32, s.len));
}
