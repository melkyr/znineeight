// capture_prong_str_literal_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Coverage-audit sibling of switch_str_literal_prong_xmod: the SAME slice-length
// corruption hits a string literal coerced to []const u8 in the prong of a switch
// EXPRESSION that CAPTURES the union payload (`|v|`), even though the captured value is
// not used in the returned literal.
//
// Bug: applyCoercion / CoercionKind.string_to_slice (sf/src/lower.zig:6623-6638) reads
// the slice length from `coercion.node_idx` only when that node is an
// AstKind.string_literal; otherwise it defaults to `sllen = 1`. A capturing
// switch-expression prong still keys its coercion on the prong/wrapper node
// (sf/src/semantic_analyzer.zig:1980-1982), so the byte length is lost. (The
// capture-binding placement itself is a separate, already-fixed defect pinned by
// switch_expr_payload_capture_xmod; this fixture isolates the string-literal length.)
//
// RED today (all 4 compilers share the defect): each prong yields a 1-byte slice, so the
// runtime assert below panics ("panic: ..." on stderr, rc=133).
// GREEN (after the lowering fix) = deterministic stdout:
//   alpha\r\n beta\r\n
// (14 bytes: "alpha\r\n" then "beta\r\n"), rc=0, no stderr.
const std = @import("std");

const U = union(enum) {
    A: u32,
    B: u32,
};

fn pick(u: U) []const u8 {
    return switch (u) {
        .A => |v| "alpha\r\n",
        .B => |v| "beta\r\n",
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
