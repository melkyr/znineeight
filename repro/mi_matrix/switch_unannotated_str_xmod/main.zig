// switch_unannotated_str_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Residual S20 (left behind by Task 0d): a switch EXPRESSION with string-literal prongs
// in an UN-ANNOTATED `var s = switch (c) {...}` position. There is NO expected type on
// the stack, so the Task 0d fix -- which gates on `topExpectedType != 0`
// (sf/src/semantic_analyzer.zig:1630-1643 switch / :1993-2000 if) -- does NOT fire. The
// result type is inferred from the FIRST prong's `*const [N:0]u8`; `s` is therefore a
// pointer to an array (emitted `char*`), not a slice, and coercing it to `[]const u8`
// loses the byte length (the string_to_slice coercion on a non-literal node defaults
// `sllen = 1`).
//
// Both prongs are the same length (7 bytes) here, so the wrong inferred type is the sole
// cause. `show` observes `a|1` instead of `alpha\r\n|7`; the assert trips.
//
// RED today: dump rc=0 / gcc-clean / link rc=0 / run rc=133 (assert trap). GREEN after
// the Task 0f S20 fix (peer-type-resolve the prongs to []const u8 and record the
// string_to_slice coercion on each prong node) = `alpha\r\n|7` then `gamma\r\n|7`,
// run rc=0.
//
// A DIRECT `s.len` on the raw inferred pointer-to-array is a harder facet of the SAME
// gap: it emits a reference to an undeclared temp and gcc-FAILs (`'zT_..' undeclared`).
// This fixture coerces through a slice (as a real Zig user must) so it stays a runtime
// gate, not a compile gate.
//
// The tag is driven through @intToEnum because a bare plain-enum literal in value
// position is mis-lowered by a SEPARATE pre-existing gap (pinned by
// bare_enum_literal_xmod).
const std = @import("std");

const Cmd = enum { A, B };

fn pick(c: Cmd) []const u8 {
    var s = switch (c) {
        .A => "alpha\r\n",
        .B => "gamma\r\n",
    };
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
    var a = pick(@intToEnum(Cmd, 0));
    show(a);
    if (!eq(a, "alpha\r\n")) { @panic("switch_unannotated_str_xmod: .A != alpha\\r\\n (un-annotated inference)"); }
    var b = pick(@intToEnum(Cmd, 1));
    show(b);
    if (!eq(b, "gamma\r\n")) { @panic("switch_unannotated_str_xmod: .B != gamma\\r\\n (un-annotated inference)"); }
}
