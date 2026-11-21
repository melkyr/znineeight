// D7.3 sibling probe: the direct slice assignment with an ARRAY right-hand
// side (`recs[i].data[0..] = buf`). Exercises the array-to-pointer source path
// of the slice-copy lowering (no slice-expression RHS).
// GREEN contract: stdout `31 34\n`, rc 0.
const std = @import("std");

const Rec = struct { data: [4]u8, score: u32 };

var recs: [2]Rec = undefined;

pub fn main() void {
    var buf: [4]u8 = [4]u8{ 31, 32, 33, 34 };
    recs[1].data[0..] = buf;
    std.io.printInt(@intCast(i32, recs[1].data[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, recs[1].data[3]));
    std.io.writeByte('\n');
}
