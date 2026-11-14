const std = @import("std");
const Node = struct { payload: u64 };
var node = Node{ .payload = 0xFFFFFFFF00000000 };
pub fn main() void {
    var n = node.payload & @intCast(u64, 0xFFFFFFFF);
    std.io.printInt(@intCast(u32, n));
}
