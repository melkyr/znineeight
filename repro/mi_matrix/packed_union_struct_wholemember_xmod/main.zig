// packed_union_struct_wholemember_xmod — PACK-AGG AMENDMENT F-1 whole-member
//   clean-reject probe. A whole packed-struct member of a packed union has no
//   bit-slice value move: `var c: Inner = u.b;` must be a single clean
//   error[3000] (rc=2, 0 .c), never silent.
const std = @import("std");

const Inner = packed struct { x: u3, y: u3 };
const U = packed union { a: u4, b: Inner };

pub fn main() void {
    var u: U = undefined;
    var c: Inner = u.b;
    std.io.printInt(@intCast(i32, c.x));
    std.io.writeByte('\n');
}
