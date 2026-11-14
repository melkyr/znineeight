// packed_l0_flags_xmod — FEATURE-GAP RED fixture (packed struct, L0: bool flags).
// Feature: `packed struct` true bitfields, LSB-first, no padding.
// RED today: `packed` not a keyword -> clean FAIL (parse). RECORD ACTUAL.
// GREEN (contract): "1 5 1\n" — 3 bools = 1 byte; a=true(c=bit0), b=false,
//   c=true(bit2) => byte 0b00000101 = 5; field reads 1 (a&&!b&&c).
const std = @import("std");

const Flags = packed struct {
    a: bool,
    b: bool,
    c: bool,
};

pub fn main() void {
    var f: Flags = undefined;
    f.a = true;
    f.b = false;
    f.c = true;
    std.io.printInt(@intCast(i32, @sizeOf(Flags)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &f);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    if (f.a and (!f.b) and f.c) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte('\n');
}
