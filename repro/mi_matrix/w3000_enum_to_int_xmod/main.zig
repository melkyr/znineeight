// w3000_enum_to_int_xmod — Task 0k warning[3000] pin (INVALID Z98 -> (b)).
//
// `var x: u32 = E.B;` assigns an enum value to an integer WITHOUT `@enumToInt`.
// The Z98 spec exposes `@enumToInt(expr)` for enum->integer
// (Language_Spec_Z98.md:298) and defines no implicit enum->integer coercion;
// the compiler's own type model agrees (CoercionKind has no enum->int arm,
// `sf/src/coercion.zig:1-19`). The current frontend only WARNS
// (`warning[3000]`, level 1, `sf/src/semantic_analyzer.zig:2984-2993`), so
// emission continues and the C enum ordinal is assigned.
//
// Classification (Task 0k): (b) invalid Zig — must become a hard
// `error[3000]` (0 `.c`). The compiler's own source relies on this construct at
// seven sites (see Task 0k report), so Task 0l must also rewrite those to
// `@enumToInt`.
//
// Runtime (today): the mismatch is harmless in C (enum is an int), so the
// program prints the correct ordinal `1`.
const std = @import("std");
const E = enum { A, B };

pub fn main() void {
    var x: u32 = E.B;
    if (x != 1) { @panic("w3000_enum_to_int_xmod: E.B != 1"); }
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
