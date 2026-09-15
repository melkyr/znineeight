// switch_unannotated_diffstr_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// Residual S20, DIFFERING-LENGTH variant of switch_unannotated_str_xmod. A switch
// EXPRESSION with string-literal prongs of DIFFERENT lengths (7 and 6 bytes) in an
// UN-ANNOTATED `var s = switch (c) {...}` position. No expected type was on the stack, so
// the Task 0d fix (topExpectedType != 0 gate) did not fire; the result type was inferred
// from the FIRST prong's `*const [N:0]u8`, and the differing-length literal could not
// unify (in real Zig this is a peer-type-resolution mismatch). zig1 silently kept the
// first prong's pointer-to-array type and the later slice coercion lost the length
// (string_to_slice on a non-literal node defaulted `sllen = 1`).
//
// FIXED in Task 0f (Track4 S20 F): the un-annotated string-literal prongs peer-type-
// resolve to `[]const u8`, recording the `string_to_slice` coercion on each prong node.
//
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n|7` then
// `beta\r\n|6`.
//
// See switch_unannotated_str_xmod for the shared locus and the direct-`s.len` gcc-FAIL
// facet; the tag is driven through @intToEnum (bare plain-enum literals are a separate
// pre-existing gap pinned by bare_enum_literal_xmod).
const std = @import("std");

const Cmd = enum { A, B };

fn pick(c: Cmd) []const u8 {
    var s = switch (c) {
        .A => "alpha\r\n",
        .B => "beta\r\n",
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
    if (!eq(a, "alpha\r\n")) { @panic("switch_unannotated_diffstr_xmod: .A != alpha\\r\\n (un-annotated diff-length inference)"); }
    var b = pick(@intToEnum(Cmd, 1));
    show(b);
    if (!eq(b, "beta\r\n")) { @panic("switch_unannotated_diffstr_xmod: .B != beta\\r\\n (un-annotated diff-length inference)"); }
}
