// relational_enum_overaccept_xmod — KNOWN OVER-ACCEPTANCE pin (NOT desired behavior).
//
// REAL ZIG REJECTS relational comparison of enum operands (`<`, `<=`, `>`, `>=`):
// enums are ordered by declaration but the language does not define `<` etc. on
// them (only `==`/`!=` are permitted). This compiler ACCEPTS them.
//
// Locus: `sf/src/semantic_analyzer.zig:1218-1219` (post-Task-0m numbering) — the
// family-B arm added by the Task 0l fix set returns `TYPE_BOOL` for `lhs == rhs`
// enum operands inside `semanticAnalyzerResolveComparison`, but is NOT gated on
// `cmp_eq`/`cmp_ne`, so it also accepts `cmp_lt`/`cmp_le`/`cmp_gt`/`cmp_ge`.
// This over-acceptance is inherited verbatim from the Task 0l fix set (applied by
// Task 0m) and is DECLARED here, not fixed. Candidate for Task 0q / a follow-up.
//
// Today: dump rc=0 / 0 `warning[3000]` / gcc-clean / link rc=0 / run rc=0,
// stdout `12345` (the comparisons evaluate by declaration tag, which is exactly
// the behavior real Zig forbids). If a future task gates the arm on
// `cmp_eq`/`cmp_ne`, this fixture should move to a hard `error[3000]`.
const std = @import("std");

const E = enum { A, B, C };

pub fn main() void {
    var a: E = .A;
    var b: E = .B;
    if (a < b) { std.io.writeByte('1'); } else { std.io.writeByte('0'); }
    if (a <= b) { std.io.writeByte('2'); } else { std.io.writeByte('0'); }
    if (b > a) { std.io.writeByte('3'); } else { std.io.writeByte('0'); }
    if (b >= a) { std.io.writeByte('4'); } else { std.io.writeByte('0'); }
    if (E.A < E.B) { std.io.writeByte('5'); } else { std.io.writeByte('0'); }
    std.io.writeByte('\n');
}
