const std = @import("std");

pub const T = struct {
    announce_list: [][]const u8,
    piece_hashes: [][20]u8,
};

pub fn main() void {
    var buf: [64]u8 = undefined;
    var inner: []const u8 = buf[0..4];
    var list: [1][]const u8 = undefined;
    list[0] = inner;
    var hashes: [1][20]u8 = undefined;
    var t: T = .{ .announce_list = list[0..1], .piece_hashes = hashes[0..1] };
    std.io.printInt(@intCast(i32, t.announce_list.len));
    std.io.printInt(@intCast(i32, t.piece_hashes.len));
    std.io.writeByte('\n');
}
