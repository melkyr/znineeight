// packed_nested_whole_depth_reject_xmod — FX15-F fix round 1: the per-leaf
// whole-value nested packed move recursion is bounded at 32 nesting levels; a
// move whose field type nests 34 packed structs deep (L0..L33 under the L34
// field) is a clean level-0 `error[3000]`, never a fall-through to the
// gcc-invalid whole-aggregate bitfield store (the pre-fix-round hole).
//
// Each of the two sites (whole-field assignment, whole-value read) emits
// exactly one level-0 `error[3000]` (rc 2, 0 `.c`, no signal); the shallower
// boundary control is `packed_nested_whole_depth_ok_xmod`.
const std = @import("std");
const L0 = packed struct { b: bool };
const L1 = packed struct { a: L0 };
const L2 = packed struct { a: L1 };
const L3 = packed struct { a: L2 };
const L4 = packed struct { a: L3 };
const L5 = packed struct { a: L4 };
const L6 = packed struct { a: L5 };
const L7 = packed struct { a: L6 };
const L8 = packed struct { a: L7 };
const L9 = packed struct { a: L8 };
const L10 = packed struct { a: L9 };
const L11 = packed struct { a: L10 };
const L12 = packed struct { a: L11 };
const L13 = packed struct { a: L12 };
const L14 = packed struct { a: L13 };
const L15 = packed struct { a: L14 };
const L16 = packed struct { a: L15 };
const L17 = packed struct { a: L16 };
const L18 = packed struct { a: L17 };
const L19 = packed struct { a: L18 };
const L20 = packed struct { a: L19 };
const L21 = packed struct { a: L20 };
const L22 = packed struct { a: L21 };
const L23 = packed struct { a: L22 };
const L24 = packed struct { a: L23 };
const L25 = packed struct { a: L24 };
const L26 = packed struct { a: L25 };
const L27 = packed struct { a: L26 };
const L28 = packed struct { a: L27 };
const L29 = packed struct { a: L28 };
const L30 = packed struct { a: L29 };
const L31 = packed struct { a: L30 };
const L32 = packed struct { a: L31 };
const L33 = packed struct { a: L32 };
const L34 = packed struct { a: L33 };

pub fn main() i32 {
    var m: L33 = undefined;
    var o: L34 = undefined;
    o.a = m;
    var r: L33 = o.a;
    _ = r;
    return 0;
}
