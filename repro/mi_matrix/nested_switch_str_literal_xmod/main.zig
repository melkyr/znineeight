// nested_switch_str_literal_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Coverage-audit sibling of switch_str_literal_prong_xmod: the SAME slice-length
// corruption hits a string literal coerced to []const u8 in the prong of a switch
// EXPRESSION that is itself the prong value of an outer switch EXPRESSION (nested
// switch-as-expression).
//
// Bug: applyCoercion / CoercionKind.string_to_slice (sf/src/lower.zig:6623-6638) reads
// the slice length from `coercion.node_idx` only when that node is an
// AstKind.string_literal; otherwise it defaults to `sllen = 1`. Each switch-expression
// prong keys its coercion on the prong/wrapper node
// (sf/src/semantic_analyzer.zig:1980-1982), so the byte length is lost at every nesting
// level.
//
// RED today (all 4 compilers share the defect): every nested prong yields a 1-byte slice,
// so the runtime assert below panics ("panic: ..." on stderr, rc=133).
// GREEN (after the lowering fix) = deterministic stdout:
//   alpha\r\n ax\r\n beta\r\n
// (18 bytes: "alpha\r\n" + "ax\r\n" + "beta\r\n"), rc=0, no stderr.
//
// The tags are driven through @intToEnum(C, 0/1) / @intToEnum(D, 0/1) because a bare
// plain-enum literal in value position is mis-lowered by an UNRELATED pre-existing gap.
const std = @import("std");

const C = enum { A, B };
const D = enum { X, Y };

fn pick(c: C, d: D) []const u8 {
    return switch (c) {
        .A => switch (d) {
            .X => "alpha\r\n",
            .Y => "ax\r\n",
        },
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
    var a: []const u8 = pick(@intToEnum(C, 0), @intToEnum(D, 0));
    var b: []const u8 = pick(@intToEnum(C, 0), @intToEnum(D, 1));
    var c: []const u8 = pick(@intToEnum(C, 1), @intToEnum(D, 0));
    std.io.write(a);
    std.io.write(b);
    std.io.write(c);
    if (!eq(a, "alpha\r\n")) { @panic("nested_switch_str_literal_xmod: inner .X != alpha\\r\\n (slice truncated)"); }
    if (!eq(b, "ax\r\n")) { @panic("nested_switch_str_literal_xmod: inner .Y != ax\\r\\n (slice truncated)"); }
    if (!eq(c, "beta\r\n")) { @panic("nested_switch_str_literal_xmod: outer .B != beta\\r\\n (slice truncated)"); }
}
