// unannotated_infer_samelength_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// F-M3 characterization (Track4 S22). Pins the NEW inference breadth Task 0f gave the
// un-annotated switch-expression: `var s = switch (c) { .A => "abc", .B => "xyz" };`
// with SAME-LENGTH literals now infers `[]const u8` (a real slice), where pre-Task-0f it
// inferred the first prong's `*const [N:0]u8` (pointer-to-array). Before the fix the
// same-length case unified on the array type (so it did not even fall through the
// differing-length path) and a subsequent `s.len` observed 1 (or gcc-FAILed on the direct
// pointer-to-array `s.len`). After the Task 0f S20 peer-type synthesis in
// `semanticAnalyzerResolveSwitchExpr`, the prongs peer-type-resolve to
// `typeRegistryGetOrCreateSlice(TYPE_U8, true)` and `s` is a slice.
//
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `abc|3` then `xyz|3`.
// This fixture is a permanent regression guard on the inference breadth (not a defect).
//
// Declared by Task 0g; no fix pending.
const std = @import("std");

const Cmd = enum { A, B };

fn pick(c: Cmd) []const u8 {
    var s = switch (c) {
        .A => "abc",
        .B => "xyz",
    };
    if (s.len != 3) { @panic("unannotated_infer_samelength_xmod: inferred slice s.len != 3"); }
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
    if (!eq(a, "abc")) { @panic("unannotated_infer_samelength_xmod: .A != abc"); }
    var b = pick(@intToEnum(Cmd, 1));
    show(b);
    if (!eq(b, "xyz")) { @panic("unannotated_infer_samelength_xmod: .B != xyz"); }
}
