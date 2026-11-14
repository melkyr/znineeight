// packed_union_struct_wholemember_xmod — FX15-F (A-full): whole-member moves
//   of a packed-struct member of a packed union are per-leaf. The former
//   clean-reject contract (PACK-AGG AMENDMENT F-1: `var c: Inner = u.b;` must
//   reject `error[3000]`) is superseded by the operator's A-full ruling: the
//   whole-value read now works, so this fixture is a positive pin (gcc-clean,
//   deterministic stdout `2 3`, rc 0). Per-leaf init keeps it deterministic.
const std = @import("std");

const Inner = packed struct { x: u3, y: u3 };
const U = packed union { a: u4, b: Inner };

pub fn main() void {
    var u: U = undefined;
    u.b.x = 2;
    u.b.y = 3;
    var c: Inner = u.b;
    std.io.printInt(@intCast(i32, c.x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, c.y));
    std.io.writeByte('\n');
}
