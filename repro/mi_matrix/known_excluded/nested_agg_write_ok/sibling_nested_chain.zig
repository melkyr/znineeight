// D7.3 sibling probe: a slice through a deeper index/field chain
// (`outers[i].mids[j].inner.bytes[0..]`) must write the real storage.
const std = @import("std");

const Inner = struct { bytes: [2]u8 };
const Mid = struct { inner: Inner };
const Outer = struct { mids: [2]Mid };

var outers: [2]Outer = undefined;

fn fill(dst: []u8) void {
    dst[0] = 5;
    dst[1] = 6;
}

pub fn main() void {
    fill(outers[1].mids[0].inner.bytes[0..]);
    std.io.printInt(@intCast(i32, outers[1].mids[0].inner.bytes[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, outers[1].mids[0].inner.bytes[1]));
    std.io.writeByte('\n');
}
