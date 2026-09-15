// if_unannotated_str_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S20, `if`-expression variant of switch_unannotated_str_xmod. An `if`/`else`
// EXPRESSION with string-literal branches in an UN-ANNOTATED
// `var s = if (b) "..." else "..."` position. No expected type was on the stack, so the
// Task 0d if-expression fix (which gates on `topExpectedType != 0`,
// sf/src/semantic_analyzer.zig:1993-2000) did NOT fire; the result type was inferred
// from the first branch's `*const [N:0]u8` and coercing the inferred pointer-to-array to
// `[]const u8` lost the byte length (`sllen = 1`).
//
// FIXED in Task 0f (Track4 S20 F): in `semanticAnalyzerResolveIfExpr`, when there is no
// expected type, string-literal branches peer-type-resolve to `[]const u8`, recording
// the `string_to_slice` coercion on each branch node.
//
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n|7` then
// `gamma\r\n|7`.
//
// See switch_unannotated_str_xmod for the shared locus and the direct-`s.len` gcc-FAIL
// facet.
const std = @import("std");

fn pick(b: bool) []const u8 {
    var s = if (b) "alpha\r\n" else "gamma\r\n";
    return s;
}

fn eq(actual: []const u8, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (actual[i] != expected[i]) return false;
    }
    return true;
}

fn show(s: []const u8) void {
    std.io.write(s);
    std.io.writeByte('|');
    std.io.printInt(@intCast(i32, s.len));
    std.io.writeByte('\n');
}

pub fn main() void {
    var a = pick(true);
    show(a);
    if (!eq(a, "alpha\r\n")) { @panic("if_unannotated_str_xmod: then-branch != alpha\\r\\n (un-annotated inference)"); }
    var b = pick(false);
    show(b);
    if (!eq(b, "gamma\r\n")) { @panic("if_unannotated_str_xmod: else-branch != gamma\\r\\n (un-annotated inference)"); }
}
