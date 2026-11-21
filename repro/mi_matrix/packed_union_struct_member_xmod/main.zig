// packed_union_struct_member_xmod — PACK-AGG AMENDMENT F-1 fixture (packed union
//   with a packed-struct member; leaf access through the union member).
// GREEN (contract): "1 6 5 7\n" — Inner{x@0 w3, y@3 w3} total 6 bits => size 1;
//   U{a@0 w4, b@0 w6} max 6 => size 1, bitSize 6; u.b.x / u.b.y read back.
const std = @import("std");

const Inner = packed struct { x: u3, y: u3 };
const U = packed union { a: u4, b: Inner };

pub fn main() void {
    var u: U = undefined;
    u.b.x = 5;
    u.b.y = 7;
    std.io.printInt(@intCast(i32, @sizeOf(U)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitSizeOf(U)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, u.b.x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, u.b.y));
    std.io.writeByte('\n');
}
