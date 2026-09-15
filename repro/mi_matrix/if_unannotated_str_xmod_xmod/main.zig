// if_unannotated_str_xmod_xmod — RUNTIME-gated RED fixture (compile-gate OK, run PANIC).
//
// Cross-module complement to if_unannotated_str_xmod. The un-annotated
// `var s = if (b) "alpha\r\n" else "gamma\r\n";` expression lives in `mid.zig` — a
// NON-LAST module (main.zig imports mid.zig then last.zig). See
// switch_unannotated_str_xmod for the shared S20 locus.
//
// RED today: dump rc=0 / gcc-clean / link rc=0 / run rc=133 (assert trap). GREEN after
// the Task 0f S20 fix = `alpha\r\n|7` then `gamma\r\n|7`, run rc=0.
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
    var a = mid.pick(true);
    show(a);
    if (!eq(a, "alpha\r\n")) { @panic("if_unannotated_str_xmod_xmod: mid.pick(true) != alpha\\r\\n (un-annotated inference)"); }
    var b = mid.pick(false);
    show(b);
    if (!eq(b, "gamma\r\n")) { @panic("if_unannotated_str_xmod_xmod: mid.pick(false) != gamma\\r\\n (un-annotated inference)"); }
    if (last.ping() != 1) { @panic("if_unannotated_str_xmod_xmod: last.ping() != 1"); }
}
