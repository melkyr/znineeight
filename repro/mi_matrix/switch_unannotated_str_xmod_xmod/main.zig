// switch_unannotated_str_xmod_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Cross-module complement to switch_unannotated_str_xmod. The un-annotated
// `var s = switch (c) { .A => "alpha\r\n", .B => "gamma\r\n" };` expression lives in
// `mid.zig` — a NON-LAST module: main.zig imports mid.zig (module 1) then last.zig
// (module 2), so mid is neither first nor last and per-module emission grouping is
// exercised. This proves the residual S20 inference gap holds across a module boundary.
//
// Residual S20 (see switch_unannotated_str_xmod for the full locus): with NO expected
// type on the stack the Task 0d fix (topExpectedType != 0) does not fire; the switch
// result is inferred from the first prong's `*const [N:0]u8` and the `return s`
// slice coercion loses the byte length (`sllen = 1`).
//
// RED today: dump rc=0 / gcc-clean / link rc=0 / run rc=133 (assert trap). GREEN after
// the Task 0f S20 fix = `alpha\r\n|7` then `gamma\r\n|7`, run rc=0.
//
// The tag is driven through @intToEnum (bare plain-enum literals are a separate
// pre-existing gap pinned by bare_enum_literal_xmod).
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

fn show(s: []const u8) void {
    std.io.write(s);
    std.io.writeByte('|');
    std.io.printInt(@intCast(i32, s.len));
    std.io.writeByte('\n');
}

pub fn main() void {
    var a = mid.pick(@intToEnum(mid.Cmd, 0));
    show(a);
    if (!eq(a, "alpha\r\n")) { @panic("switch_unannotated_str_xmod_xmod: mid.pick(.A) != alpha\\r\\n (un-annotated inference)"); }
    var b = mid.pick(@intToEnum(mid.Cmd, 1));
    show(b);
    if (!eq(b, "gamma\r\n")) { @panic("switch_unannotated_str_xmod_xmod: mid.pick(.B) != gamma\\r\\n (un-annotated inference)"); }
    if (last.ping() != 1) { @panic("switch_unannotated_str_xmod_xmod: last.ping() != 1"); }
}
