// capture_prong_str_literal_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// Coverage-audit sibling of switch_str_literal_prong_xmod: a string literal coerced to
// []const u8 in the prong of a switch EXPRESSION that CAPTURES the union payload (`|v|`).
// The Task-0c review flagged the original version as redundant (the unused `|v|` capture
// was elided). The capture is now USED to select the returned literal, so the binding is
// live and this fixture exercises the capturing-prong path distinctly: a mis-bound or
// elided capture selects "wrongA"/"wrongB" and trips the runtime assert.
//
// Bug: applyCoercion / CoercionKind.string_to_slice (sf/src/lower.zig:6623-6638) reads
// the slice length from `coercion.node_idx` only when that node is an
// AstKind.string_literal; otherwise it defaults to `sllen = 1`. A capturing
// switch-expression prong keyed its coercion on the prong/wrapper node, so the byte
// length was lost. (The capture-binding placement itself is a separate, already-fixed
// defect pinned by switch_expr_payload_capture_xmod.)
//
// FIXED in Task 0d: the switch-expression resolver now coerces each string-literal prong
// directly to the expected []const u8 (recording the coercion on the literal node), so
// applyCoercion reads the real byte length instead of defaulting to 1.
// GREEN (post-fix) = dump rc=0 / gcc-clean / link rc=0 / run rc=0, deterministic stdout:
//   alpha\r\n beta\r\n
// (13 bytes: "alpha\r\n" then "beta\r\n"), no stderr.
const std = @import("std");

const U = union(enum) {
    A: u32,
    B: u32,
};

fn pick(u: U) []const u8 {
    return switch (u) {
        .A => |v| if (v == 7) "alpha\r\n" else "wrongA\r\n",
        .B => |v| if (v == 9) "beta\r\n" else "wrongB\r\n",
    };
}

fn eq(actual: []const u8, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (actual[i] != expected[i]) return false;
    }
    return true;
}

pub fn main() void {
    var a: []const u8 = pick(U{ .A = 7 });
    var b: []const u8 = pick(U{ .B = 9 });
    std.io.write(a);
    std.io.write(b);
    if (!eq(a, "alpha\r\n")) { @panic("capture_prong_str_literal_xmod: .A prong != alpha\\r\\n (slice truncated)"); }
    if (!eq(b, "beta\r\n")) { @panic("capture_prong_str_literal_xmod: .B prong != beta\\r\\n (slice truncated)"); }
}
