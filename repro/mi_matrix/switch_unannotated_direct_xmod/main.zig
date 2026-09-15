// switch_unannotated_direct_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// Task 0f Step 1/3: pins the DIRECT `s.len` facet of residual S20 that Task 0e
// declared in prose only (it had no separate dir). The un-annotated
// `var s = switch (c) { .A => "alpha\r\n", .B => "gamma\r\n" };` is followed by a
// DIRECT `s.len` on the raw inferred value (no intervening `[]const u8` coercion).
//
// PRE-FIX (Task 0e/0f base `7297eb44`): the result type was inferred from the FIRST
// prong's `*const [N:0]u8`, so `s` was a pointer-to-array; the direct `s.len` emitted a
// reference to an undeclared temp and gcc-FAILed (`'zT_..' undeclared`) — a compile gate
// failure, not merely a runtime trim.
//
// POST-FIX (Task 0f S20): the un-annotated prongs peer-type-resolve to `[]const u8`, so
// `s` is a real slice; `s.len` is the full 7-byte length and the program prints
// `alpha\r\n|7` then `gamma\r\n|7`, run rc=0.
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
    if (s.len != 7) { @panic("switch_unannotated_direct_xmod: s.len != 7 (direct un-annotated inference)"); }
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
    if (!eq(a, "alpha\r\n")) { @panic("switch_unannotated_direct_xmod: .A != alpha\\r\\n (direct un-annotated inference)"); }
    var b = pick(@intToEnum(Cmd, 1));
    show(b);
    if (!eq(b, "gamma\r\n")) { @panic("switch_unannotated_direct_xmod: .B != gamma\\r\\n (direct un-annotated inference)"); }
}
