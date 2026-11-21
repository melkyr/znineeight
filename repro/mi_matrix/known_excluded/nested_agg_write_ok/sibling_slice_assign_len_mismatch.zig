// D7.3 sibling probe: a direct slice assignment whose compile-time lengths
// differ (`recs[i].data[0..]` is 4 bytes, `longer[0..]` is 6). The lowering must
// reject cleanly instead of emitting a copy bounded by the source length that
// writes past the destination field.
// REJECT contract: rc 2, one level-0 length-mismatch diagnostic, 0 emitted `.c`.
const std = @import("std");

const Rec = struct { data: [4]u8, score: u32 };

var recs: [2]Rec = undefined;

pub fn main() void {
    var longer: [6]u8 = [6]u8{ 1, 2, 3, 4, 5, 6 };
    recs[1].data[0..] = longer[0..];
    std.io.printInt(@intCast(i32, recs[1].data[0]));
    std.io.writeByte('\n');
}
