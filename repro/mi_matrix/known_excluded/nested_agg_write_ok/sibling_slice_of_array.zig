// D7.3 sibling probe: the exact `arr[i].field[0..] = src[0..]` slice-of-array
// store (the wireguard demo workaround shape, without the pointer).
const std = @import("std");

const Rec = struct { data: [4]u8, score: u32 };

var recs: [2]Rec = undefined;

pub fn main() void {
    var buf: [4]u8 = [4]u8{ 21, 22, 23, 24 };
    recs[1].data[0..] = buf[0..];
    std.io.printInt(@intCast(i32, recs[1].data[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, recs[1].data[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, recs[1].data[2]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, recs[1].data[3]));
    std.io.writeByte('\n');
}
