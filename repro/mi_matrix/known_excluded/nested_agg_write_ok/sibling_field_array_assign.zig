// D7.3 sibling probe: the whole-array field assignment form
// (`arr[i].field = srcArray`) through an indexed base. GREEN contract: the
// lowering copies element-wise into the real field storage; stdout `21 24\n`,
// rc 0. Pre-fix this emits a C array-to-array assignment (`zT->field = src`)
// that gcc rejects.
const std = @import("std");

const Peer = struct { field: [4]u8, score: u32 };

var peers: [2]Peer = undefined;

pub fn main() void {
    var buf: [4]u8 = [4]u8{ 21, 22, 23, 24 };
    peers[1].field = buf;
    std.io.printInt(@intCast(i32, peers[1].field[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, peers[1].field[3]));
    std.io.writeByte('\n');
}
