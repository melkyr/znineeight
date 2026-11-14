// D12 sibling probe: module-scope untyped array literal whose elements are
// typed struct literals. Isolates the untyped OUTER literal from the
// array-of-anonymous-struct-literal defect (`array_of_struct_literal_xmod`).
const std = @import("std");

const Pair = struct { key: u32, val: u32 };

var sarr: [2]Pair = .{ Pair{ .key = 1, .val = 2 }, Pair{ .key = 3, .val = 4 } };

pub fn main() void {
    sarr[1].val = 9;
    std.io.printInt(@intCast(i32, sarr[0].key));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, sarr[0].val));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, sarr[1].key));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, sarr[1].val));
    std.io.writeByte('\n');
}
