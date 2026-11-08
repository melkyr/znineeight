// D7.3 sibling probe: a whole-array field assigned from another whole-array
// field (`peers[1].field = peers[0].field`) through local and global bases.
// Both sides decay to element pointers in the type system, so lowering must
// recover the declared array type and copy the field storage element-wise.
// GREEN contract: stdout `11 14 21 24\n`, rc 0, no `warning[3000]`.
const std = @import("std");

const Peer = struct { field: [4]u8, score: u32 };

var g_peers: [2]Peer = undefined;

pub fn main() void {
    var peers: [2]Peer = undefined;

    peers[0].field[0] = 11;
    peers[0].field[1] = 12;
    peers[0].field[2] = 13;
    peers[0].field[3] = 14;
    g_peers[0].field[0] = 21;
    g_peers[0].field[1] = 22;
    g_peers[0].field[2] = 23;
    g_peers[0].field[3] = 24;

    peers[1].field = peers[0].field;
    g_peers[1].field = g_peers[0].field;

    std.io.printInt(@intCast(i32, peers[1].field[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, peers[1].field[3]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g_peers[1].field[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g_peers[1].field[3]));
    std.io.writeByte('\n');
}
