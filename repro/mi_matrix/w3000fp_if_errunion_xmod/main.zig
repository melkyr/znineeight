// w3000fp_if_errunion_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `var r: E!i32 = if (c) error.Bad else 0;` — with the expected type `E!i32`,
// the error literal coerces via `wrap_error_err` and the integer literal via
// `wrap_error_success`. `semanticAnalyzerResolveIfExpr` only honors the expected
// type for STRING-literal prongs (`sf/src/semantic_analyzer.zig:1643-1653`) and
// otherwise returns `TYPE_VOID`, so the var-decl warns
// `source: void / target: error-union`.
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `7` (the `catch` fallback); the error is stored.
const std = @import("std");
const E = error{Bad};

pub fn main() void {
    var c: bool = true;
    var r: E!i32 = if (c) error.Bad else 0;
    var got: i32 = r catch 7;
    std.io.printInt(got);
    std.io.writeByte('\n');
}
