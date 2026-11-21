// switch_str_literal_prong_xmod_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// Cross-module complement to switch_str_literal_prong_xmod. The buggy switch-expression
// with string-literal prongs lives in `mid.zig` — a NON-LAST module: `main.zig` imports
// `mid.zig` (module 1) then `last.zig` (module 2), so `mid` is neither first nor last and
// the per-module emission grouping is exercised. This proves the same string-prong
// slice-length corruption (and, after the fix, its absence) holds across a module
// boundary, not only in the module that owns `main`.
//
// Bug: see switch_str_literal_prong_xmod — applyCoercion / CoercionKind.string_to_slice
// (sf/src/lower.zig:6623-6638) reads the slice length from `coercion.node_idx` only when
// that node is an AstKind.string_literal, else defaults to 1; a switch-expression prong
// keys its coercion on the prong/wrapper node (sf/src/semantic_analyzer.zig:1980-1982),
// so the length is lost.
//
// FIXED in Task 0d: the switch-expression resolver now coerces each string-literal prong
// directly to the expected []const u8 (recording the coercion on the literal node), so
// applyCoercion reads the real byte length instead of defaulting to 1.
// GREEN (post-fix) = dump rc=0 / gcc-clean / link rc=0 / run rc=0, deterministic stdout:
//   alpha\r\n beta\r\n
// (13 bytes: "alpha\r\n" then "beta\r\n"), no stderr.
//
// The tag is driven through @intToEnum(mid.Cmd, 0/1) because a bare plain-enum literal in
// value position (.A) is mis-lowered by an UNRELATED pre-existing gap; @intToEnum is
// correct (verified).
const std = @import("std");
const mid = @import("mid.zig");
const last = @import("last.zig");

fn eq(actual: []const u8, expected: []const u8) bool {
    if (actual.len != expected.len) return false;
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        if (actual[i] != expected[i]) return false;
    }
    return true;
}

pub fn main() void {
    var a: []const u8 = mid.pick(@intToEnum(mid.Cmd, 0));
    var b: []const u8 = mid.pick(@intToEnum(mid.Cmd, 1));
    std.io.write(a);
    std.io.write(b);
    if (!eq(a, "alpha\r\n")) { @panic("switch_str_literal_prong_xmod_xmod: mid.pick(.A) != alpha\\r\\n (slice truncated)"); }
    if (!eq(b, "beta\r\n")) { @panic("switch_str_literal_prong_xmod_xmod: mid.pick(.B) != beta\\r\\n (slice truncated)"); }
    if (last.ping() != 1) { @panic("switch_str_literal_prong_xmod_xmod: last.ping() != 1"); }
}
