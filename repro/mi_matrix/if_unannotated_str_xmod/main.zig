// if_unannotated_str_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Residual S20, `if`-expression variant of switch_unannotated_str_xmod. An `if`/`else`
// EXPRESSION with string-literal branches in an UN-ANNOTATED
// `var s = if (b) "..." else "..."` position. No expected type is on the stack, so the
// Task 0d if-expression fix (which gates on `topExpectedType != 0`,
// sf/src/semantic_analyzer.zig:1993-2000) does NOT fire; the result type is inferred
// from the first branch's `*const [N:0]u8` and coercing the inferred pointer-to-array to
// `[]const u8` loses the byte length (`sllen = 1`).
//
// RED today: dump rc=0 / gcc-clean / link rc=0 / run rc=133 (assert trap). GREEN after
// the Task 0f S20 fix (peer-type-resolve the branches to []const u8, recording the
// string_to_slice coercion on each branch node) = `alpha\r\n|7` then `gamma\r\n|7`,
// run rc=0.
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
