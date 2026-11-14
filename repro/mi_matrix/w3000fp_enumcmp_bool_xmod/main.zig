// w3000fp_enumcmp_bool_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// ROOT CAUSE of the self `bool`-from-`and`/`or` family
// (`sf/src/semantic_analyzer.zig:1639-1640`, `sf/src/c89_emit.zig:745`): it is
// NOT the `and`/`or`; it is the ENUM COMPARISON underneath. `k == E.a` where
// both operands have the same enum type resolves to `void` because
// `semanticAnalyzerResolveComparison` returns `bool` only for numeric/bool/
// pointer/optional/error-set operand pairs (`sf/src/semantic_analyzer.zig:
// 1206-1218`) and falls through to `TYPE_VOID` for enum==enum (`:1220`).
// `bool = <enum cmp>` therefore warns `source: void / target: bool`, and any
// `and`/`or` over two such comparisons also resolves to `void`.
//
// Real Zig permits `==`/`!=` on enums and yields `bool`; this is a
// type-checker false positive.
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file
// (check: `scripts/corpus/w3000_census.sh <zig1>` over the Task-0l pin set).
//
// Runtime (today): prints `1`; comparison results are correct at runtime.
const std = @import("std");
const E = enum { a, b };

pub fn main() void {
    var k: E = E.a;
    var eq: bool = k == E.a;
    var ne: bool = k != E.b;
    if (eq and ne) { std.io.printInt(@intCast(i32, 1)); } else { std.io.printInt(@intCast(i32, 0)); }
    std.io.writeByte('\n');
}
