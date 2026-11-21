// w3000fp_if_optional_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `var r: ?i32 = if (c) null else 0;` — with the expected type `?i32`, `null`
// coerces via `wrap_optional_null` and the integer literal via `wrap_optional`.
// `semanticAnalyzerResolveIfExpr` (`sf/src/semantic_analyzer.zig:1643-1653`)
// only honors the expected type for STRING-literal prongs, then falls through to
// `TYPE_VOID`, so the var-decl warns `source: void / target: optional`.
//
// Real Zig coerces both prongs to the expected optional; this is a type-checker
// false positive.
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `1`; `null` is stored correctly.
const std = @import("std");

pub fn main() void {
    var c: bool = true;
    var r: ?i32 = if (c) null else 0;
    if (r == null) { std.io.printInt(@intCast(i32, 1)); } else { std.io.printInt(@intCast(i32, 0)); }
    std.io.writeByte('\n');
}
