// a1_strlit_ptrarray_warn_xmod — A1 warning-regression repro (Task 0i residual pin).
//
// Track4 S23 I. Task 0h typed string literals `*const [N]u8`
// (`sf/src/semantic_analyzer.zig` string_literal arm; `sf/src/lower.zig`
// `lowerExprImpl` string_literal arm). The C emitter renders that temp as a
// pointer-to-array `unsigned char (*)[N]`, so the minimal `var s: []const u8 =
// "abc";` emits TWO `[-Wincompatible-pointer-types]` warnings:
//
//   zT_1 = "abc";       // warning: assignment to 'unsigned char (*)[3]'
//                       //   from incompatible pointer type 'char *'
//   zT_2.ptr = zT_1;    // warning: assignment to 'unsigned char *'
//                       //   from incompatible pointer type 'unsigned char (*)[3]'
//
// Measured (`gcc -m32 -std=c89 -O0 -Wall -Wextra -fsyntax-only`, user code only):
//   pre-0h  (97cd5a03): 0 warnings
//   post-0h (958a5e0f): 2 warnings
// Corpus-wide user-code warning census (641 dirs, `-Wall -Wextra`):
//   pre-0h 144 / post-0h 1504; the entire +1360 delta is
//   `-Wincompatible-pointer-types` in 102 dirs (0 improved); every other
//   category is byte-identical. Examples: json_parser 1 -> 60,
//   lisp_interpreter_curr 1 -> 107, mud_server 8 -> 36.
//
// Corpus class: OK (warnings are non-fatal), runtime byte-identical (the 4-MD5
// runtime proof). EXPECTED after Task 0j: ZERO `-Wincompatible-pointer-types`
// warnings (fix options: decay the `string_const` temp to a plain pointer, or
// cast the pointer-to-array temp at each plain-pointer use site).
const std = @import("std");

pub fn main() void {
    var s: []const u8 = "abc";
    if (s.len != 3) { @panic("a1_strlit_ptrarray_warn_xmod: s.len != 3"); }
    std.io.write(s);
    std.io.writeByte('\n');
}
