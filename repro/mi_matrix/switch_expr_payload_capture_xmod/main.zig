// switch_expr_payload_capture_xmod — RUNTIME-gated RED fixture (compile-gate OK, run CRASH/garbage).
//
// Bug: a switch used as an EXPRESSION with a payload-capture prong mis-lowers in zig1. In the
// switch-as-expression lowering (lowerExprImpl, sf/src/lower.zig, site ~4010-4219) the payload
// binding instructions (load_field TU_FIELD_PAYLOAD at ~4169, addLocalDecl + decl_local at
// ~4170-4171) are emitted BEFORE `self.current_bb = prong_bb_id;` (~4180), so they land in the
// wrong block: in an exhaustive no-else switch they go into the dead synthetic default
// fall-through (never executed); with an else prong they go into the dispatch block between the
// switch_br and the first case label (skipped by the tag-dispatch goto). The capture name is
// therefore read UNINITIALIZED. The switch-as-statement lowering (lowerStmt, sf/src/lower.zig,
// site ~4913-5064) sets `self.current_bb = prong_bb_id;` (~5026) BEFORE the capture emissions
// (~5028-5052), so its captures land inside the prong block after the case label and are correct.
//
// This fixture extracts a payload slice from the SAME union value two ways and prints the
// captured payload whole, so a correct compiler prints identical evidence from both paths:
//   (a) const expr_key = switch (kv) { .A => |s| s, .B => |s| s };   -- expression switch (BUG)
//   (b) stmtExtract(kv) helper                                   -- statement-switch sibling
// k drives the union tag: k=0 -> .A payload "helloA", k=1 -> .B payload "helloB".
//
// RED today (all 4 compilers share the defect): run SIGSEGV rc=139 or garbage stdout — the
// expression-switch result is an uninitialized slice whose whole write crashes or prints garbage.
// GREEN (after the lowering fix) = deterministic stdout:
//   helloA
//   helloA
//   helloB
//   helloB
// (28 bytes; expr-switch line then statement-sibling line for each k — identical evidence,
// verified byte-equal on the statement-only control green2.)
const std = @import("std");

const V = union(enum) {
    A: []const u8,
    B: []const u8,
};

fn pickStr(b: bool) V {
    if (b) {
        return V{ .A = "helloA" };
    } else {
        return V{ .B = "helloB" };
    }
}

fn stmtExtract(kv: V) []const u8 {
    var r: []const u8 = undefined;
    switch (kv) {
        .A => |s| r = s,
        .B => |s| r = s,
    }
    return r;
}

pub fn main() void {
    var k: usize = 0;
    while (k < 2) : (k += 1) {
        var kv = pickStr(k == 0);
        const expr_key = switch (kv) {
            .A => |s| s,
            .B => |s| s,
        };
        std.io.write(expr_key);
        std.io.writeByte('\n');
        std.io.write(stmtExtract(kv));
        std.io.writeByte('\n');
    }
}
