// switch_str_literal_prong_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Bug: a switch used as an EXPRESSION whose prong value is a string literal coerced to
// []const u8 is emitted with slice length 1 (only the first byte survives). In the
// string->slice coercion (applyCoercion, sf/src/lower.zig, CoercionKind.string_to_slice
// at :6623-6638) the length is read from `coercion.node_idx` ONLY when that AST node is
// an AstKind.string_literal; otherwise it defaults to `sllen = 1`. A switch-expression
// prong records its coercion keyed on the prong/wrapper node
// (sf/src/semantic_analyzer.zig:1980-1982 `tryRecordCoercion(prong.child_0, ...)`), not
// on the literal itself, so the real byte length is lost. The switch-as-STATEMENT path
// records no wrapper-keyed coercion and is correct.
//
// This is why examples/z98/mud_server/main.zig processCommand's `.Quit => "Goodbye!\r\n"`
// (and `.Unknown => "Unknown command.\r\n"`, etc.) send only `G`/`U` — the string literal
// prong is lowered to a 1-byte slice.
//
// `pick` returns `switch (c) { .A => "alpha\r\n", .B => "beta\r\n" }` typed []const u8.
// Both prongs are printed, then a runtime assert compares each against its full expected
// string.
//
// RED today (all 4 compilers share the defect): each prong yields a 1-byte slice, so the
// runtime assert below panics ("panic: ..." on stderr, rc=133); stdout shows at most the
// first bytes.
// GREEN (after the lowering fix) = deterministic stdout:
//   alpha\r\n beta\r\n
// (14 bytes: "alpha\r\n" then "beta\r\n"), rc=0, no stderr.
//
// The tag is driven through @intToEnum(Cmd, 0/1) because a bare plain-enum literal in
// value position (.A) is mis-lowered by an UNRELATED pre-existing gap; @intToEnum is
// correct (verified) and keeps this fixture focused on the slice-length defect.
const std = @import("std");

const Cmd = enum { A, B };

fn pick(c: Cmd) []const u8 {
    return switch (c) {
        .A => "alpha\r\n",
        .B => "beta\r\n",
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
    var a: []const u8 = pick(@intToEnum(Cmd, 0));
    var b: []const u8 = pick(@intToEnum(Cmd, 1));
    std.io.write(a);
    std.io.write(b);
    if (!eq(a, "alpha\r\n")) { @panic("switch_str_literal_prong_xmod: prong .A != alpha\\r\\n (slice truncated)"); }
    if (!eq(b, "beta\r\n")) { @panic("switch_str_literal_prong_xmod: prong .B != beta\\r\\n (slice truncated)"); }
}
