// w3000_bool_or_xmod — Task 0k warning[3000] pin (VALID Z98 -> (a)).
//
// Reproduces the compiler's own `sf/src/c89_emit.zig:745`
// (`var et_is_ptr: bool = et.kind == ... or et.kind == ...;`) and
// `semantic_analyzer.zig:1639-1640` (`var x: bool = <cmp> and <cmp>;`):
// a `bool` variable initialized from a boolean `and`/`or` expression over enum
// comparisons. The checker resolves the `and`/`or` expression to `void`, so the
// var-decl warns `source: void / target: bool`.
//
// `<bool> or <bool>` is a valid Z98 boolean expression, so this is a
// type-checker false positive.
//
// Classification (Task 0k): (a) valid Z98, fix = type-checker accuracy (the
// `and`/`or` result type must be `bool`, not `void`).
//
// NOTE: use QUALIFIED enum literals (`T.a`). A bare `.a` in value position hits
// the separate, pre-existing bare-enum-literal mis-lowering
// (`bare_enum_literal_xmod`, runtime-RED) and would print the wrong value; that
// bug is distinct from this warning.
//
// Runtime (today): prints `1`.
const std = @import("std");
const T = enum { a, b };

pub fn main() void {
    var et: T = T.a;
    var b: bool = et == T.a or et == T.b;
    if (b) { std.io.printInt(@intCast(i32, 1)); } else { std.io.printInt(@intCast(i32, 0)); }
    std.io.writeByte('\n');
}
