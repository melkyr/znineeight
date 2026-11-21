// a1_ptrarray_cchar_xmod — Task 0k pointer-shape 2 pin (A1 C-model).
//
// Track4 S24 I. A1 types string literals `*const [N]u8`. The C emitter
// (`sf/src/c89_emit.zig` getCTypeName, ptr_type arm) renders that temp as a
// pointer-to-array `unsigned char (*)[N]`. Shape 2 is the materialization of
// that temp to a `[*]const c_char` (emitted `char*`):
//
//   zT_B..._Arr_unsigned_char_3* zT_2;
//   char* zT_1;
//   zT_2 = "abc";   // warning: assignment to 'unsigned char (*)[3]' from
//                   //          incompatible pointer type 'char *'   (shape 1)
//   zT_1 = zT_2;    // warning: assignment to 'char *' from incompatible
//                   //          pointer type 'unsigned char (*)[3]' (shape 2)
//
// Underlying Zig: `fn firstByte(p: [*]const c_char)` called with the string
// literal `"abc"`; the literal is `*const [3]u8` and coerces to the many-item
// pointer parameter (Language_Spec_Z98.md:72,383). VALID Z98. The defect is
// purely the C model of `*const [N]u8` (pointer-to-array instead of a plain
// element pointer).
//
// Measured (user code, `-Wall -Wextra -Wno-pointer-sign`):
//   pre-A1  (97cd5a03): 0 warnings
//   post-A1 (958a5e0f): 2 `[-Wincompatible-pointer-types]` (shapes 1 + 2)
// Contract: runs and prints `97`; EXPECTED after Task 0j: 0 pointer warnings.
const std = @import("std");

fn firstByte(p: [*]const c_char) u8 { return @intCast(u8, p[0]); }

pub fn main() void {
    var b: u8 = firstByte("abc");
    if (b != 97) { @panic("a1_ptrarray_cchar_xmod: firstByte != 97"); }
    std.io.printInt(@intCast(i32, b));
    std.io.writeByte('\n');
}
