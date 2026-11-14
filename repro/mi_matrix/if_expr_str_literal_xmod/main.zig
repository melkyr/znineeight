// if_expr_str_literal_xmod — RUNTIME-gated GREEN fixture (compile-gate OK, run rc=0).
//
// Coverage-audit sibling of switch_str_literal_prong_xmod: the SAME slice-length
// corruption hits string literals coerced to []const u8 in an `if`/`else` EXPRESSION
// (both `return if (...) "..." else "..."` and `var s: []const u8 = if (...) ...`).
//
// Bug: applyCoercion / CoercionKind.string_to_slice (sf/src/lower.zig:6623-6638) reads
// the slice length from `coercion.node_idx` only when that node is an
// AstKind.string_literal; otherwise it defaults to `sllen = 1`. An `if`-expression
// branch records its coercion keyed on the branch/wrapper node (not the literal), so the
// byte length is lost. The if-STATEMENT form (`if (b) { return "..."; }`) is unaffected
// (verified — it is not an expression coercion).
//
// `pick` = `return if (b) "alpha\r\n" else "beta\r\n"`; `direct` exercises the var-init
// if-expression form.
//
// FIXED in Task 0d: the if-expression resolver now coerces each string-literal branch
// directly to the expected []const u8 (recording the coercion on the branch node), so
// applyCoercion reads the real byte length instead of defaulting to 1.
// GREEN (post-fix) = dump rc=0 / gcc-clean / link rc=0 / run rc=0, deterministic stdout:
//   alpha\r\n beta\r\n gamma\r\n
// (20 bytes: "alpha\r\n" + "beta\r\n" + "gamma\r\n"), no stderr.
const std = @import("std");

fn pick(b: bool) []const u8 {
    return if (b) "alpha\r\n" else "beta\r\n";
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
    var a: []const u8 = pick(true);
    var b: []const u8 = pick(false);
    var c: []const u8 = if (true) "gamma\r\n" else "delta\r\n";
    std.io.write(a);
    std.io.write(b);
    std.io.write(c);
    if (!eq(a, "alpha\r\n")) { @panic("if_expr_str_literal_xmod: return-if .A != alpha\\r\\n (slice truncated)"); }
    if (!eq(b, "beta\r\n")) { @panic("if_expr_str_literal_xmod: return-if .B != beta\\r\\n (slice truncated)"); }
    if (!eq(c, "gamma\r\n")) { @panic("if_expr_str_literal_xmod: var-init if != gamma\\r\\n (slice truncated)"); }
}
