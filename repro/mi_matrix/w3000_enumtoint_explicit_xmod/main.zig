// w3000_enumtoint_explicit_xmod — Task 0k warning[3000] pin (VALID Z98 -> (a)).
//
// Even the EXPLICIT, spec-blessed conversion `@enumToInt(E.B)`
// (Language_Spec_Z98.md:298) assigned to the enum's own backing integer type
// (`u32`) trips `warning[3000]` (source kind reported as `type` / target
// `u32`). That is a pure type-checker false positive: the result of a builtin
// (`@enumToInt`, `@intCast`, ...) is resolved as the *type* value instead of
// its result type. The construct is VALID Z98 and the emitted C is correct.
//
// Classification (Task 0k): (a) valid Z98, the warning is a type-checker false
// positive (fix = type-checker accuracy), NOT a hard error. This is the
// counterexample that distinguishes the (b) implicit enum->int case above.
//
// Runtime (today): prints the correct ordinal `1`.
const std = @import("std");
const E = enum { A, B };

pub fn main() void {
    var x: u32 = @enumToInt(E.B);
    if (x != 1) { @panic("w3000_enumtoint_explicit_xmod: @enumToInt(E.B) != 1"); }
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
