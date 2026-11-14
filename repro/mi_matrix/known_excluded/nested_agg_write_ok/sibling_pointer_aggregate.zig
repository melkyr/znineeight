// D7.3 sibling probe: slice through a pointer-to-aggregate (the wireguard
// demo workaround) must write the real storage.
const std = @import("std");

const Peer = struct { field: [4]u8, score: u32 };

var peers: [2]Peer = undefined;

fn fill(dst: []u8) void {
    dst[0] = 7;
    dst[1] = 8;
}

pub fn main() void {
    var pp: *Peer = &peers[1];
    fill(pp.field[0..]);
    std.io.printInt(@intCast(i32, peers[1].field[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, peers[1].field[1]));
    std.io.writeByte('\n');
}
