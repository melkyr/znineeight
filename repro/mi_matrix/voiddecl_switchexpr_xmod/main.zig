const std = @import("std");
const E = enum(u8) { struct_type, void_type };
const A = E.struct_type;
const B = E.void_type;
pub fn main() void {
    var kind: u32 = 0;
    var t = switch (kind) {
        0 => A,
        else => B,
    };
    std.io.printInt(@intCast(u32, @enumToInt(t)));
}
