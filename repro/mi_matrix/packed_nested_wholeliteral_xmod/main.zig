// packed_nested_wholeliteral_xmod — FX15-F (A-full) positive runtime pin for
// whole-value moves of nested packed sub-containers.
//
// DEFECT before the fix: a struct-literal element whose field type is a nested
// `packed struct` over-accepted and emitted a single `store_bitfield` of the
// whole aggregate carrier into a bit slice (gcc: "aggregate value used where
// an integer was expected"); the assignment form `o.inner = ...` and the
// whole-value read `var r: Inner = o.inner` cleanly rejected `error[3000]`.
//
// FIX: every whole-value move of a nested packed sub-container is a per-leaf
// `load_bitfield`/`store_bitfield` copy with composed offsets (the literal,
// assignment, packed-union and read paths agree).
//
// RED on the seed compiler (literal/assignment/read sites fail); GREEN here:
// dump rc 0, gcc clean, deterministic stdout below, RUNRC 0.
const std = @import("std");
const helper = @import("helper");

const Inner = packed struct { x: u2, y: u3 };
const Mid = packed struct { i: Inner, z: u1 };
const Outer = packed struct { first: u3, inner: Inner, last: u1 };
const OuterMid = packed struct { first: u3, mid: Mid, last: u2 };
const Big = packed struct { a: u31, b: u31 };
const OuterBig = packed struct { first: u2, inner: Big };
const PUnion = packed union { a: u3, inner: Inner };
const OuterH = packed struct { first: u3, inner: helper.Inner, last: u1 };

pub fn main() i32 {
    // 1. struct-literal element (n1).
    var o1: Outer = .{ .first = 5, .inner = .{ .x = 2, .y = 7 }, .last = 1 };
    std.io.print("lit {} {} {}\n", .{ o1.first, o1.inner.x, o1.last });

    // 2. whole-value expression element (n4).
    var i2: Inner = .{ .x = 3, .y = 1 };
    var o2: Outer = .{ .first = 2, .inner = i2, .last = 1 };
    std.io.print("val {} {}\n", .{ o2.inner.x, o2.inner.y });

    // 3. depth-2 nested literal (n6).
    var o3: OuterMid = .{ .first = 5, .mid = .{ .i = .{ .x = 2, .y = 7 }, .z = 1 }, .last = 2 };
    std.io.print("deep {} {} {}\n", .{ o3.first, o3.mid.i.x, o3.last });

    // 4. 62-bit wide nested literal (n20): two 31-bit leaves.
    var o4: OuterBig = .{ .first = 1, .inner = .{ .a = 7, .b = 9 } };
    std.io.print("wide {} {} {}\n", .{ o4.first, o4.inner.a, o4.inner.b });

    // 5. whole-field assignment through the packed holder (n2).
    var o5: Outer = undefined;
    o5.first = 5;
    o5.inner = .{ .x = 2, .y = 7 };
    o5.last = 1;
    std.io.print("assign {} {} {}\n", .{ o5.first, o5.inner.x, o5.last });

    // 6. whole-value read out of a nested field (n19).
    var r6: Inner = o5.inner;
    std.io.print("read {} {}\n", .{ r6.x, r6.y });

    // 7. packed union: whole-member literal, assignment and read.
    var u7: PUnion = .{ .inner = .{ .x = 2, .y = 7 } };
    std.io.print("pu-l {} {}\n", .{ u7.inner.x, u7.inner.y });
    u7.inner = .{ .x = 1, .y = 3 };
    var r7: Inner = u7.inner;
    std.io.print("pu-a {} {} {}\n", .{ r7.x, r7.y, u7.inner.y });

    // 8. cross-module literal + whole-value read.
    var o8: helper.Outer = .{ .first = 5, .inner = .{ .x = 2, .y = 7 }, .last = 1 };
    var r8: helper.Inner = o8.inner;
    std.io.print("xmod {} {} {}\n", .{ o8.first, r8.x, r8.y });

    // 9. local holder with a cross-module nested field type.
    var o9: OuterH = .{ .first = 4, .inner = .{ .x = 1, .y = 2 }, .last = 0 };
    std.io.print("xmod2 {} {} {}\n", .{ o9.first, o9.inner.x, o9.last });
    return 0;
}
