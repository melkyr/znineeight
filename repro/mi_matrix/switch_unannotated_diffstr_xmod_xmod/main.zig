// switch_unannotated_diffstr_xmod_xmod — RUNTIME-gated GREEN fixture (compile-gate OK,
// run rc=0).
//
// Cross-module complement to switch_unannotated_diffstr_xmod. The un-annotated
// `var s = switch (c) { .A => "alpha\r\n", .B => "beta\r\n" };` expression (DIFFERING
// literal lengths, 7 and 6) lives in `mid.zig` — a NON-LAST module (main.zig imports
// mid.zig then last.zig). See switch_unannotated_str_xmod for the shared S20 locus.
//
// FIXED in Task 0f (Track4 S20 F): the un-annotated differing-length prongs peer-type-
// resolve to `[]const u8`, so the result is a real slice across the module boundary.
//
// GREEN today: dump rc=0 / gcc-clean / link rc=0 / run rc=0; stdout `alpha\r\n|7` then
// `beta\r\n|6`.
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
    if (!eq(a, "alpha\r\n")) { @panic("switch_unannotated_diffstr_xmod_xmod: mid.pick(.A) != alpha\\r\\n (un-annotated diff-length inference)"); }
    var b = mid.pick(@intToEnum(mid.Cmd, 1));
    show(b);
    if (!eq(b, "beta\r\n")) { @panic("switch_unannotated_diffstr_xmod_xmod: mid.pick(.B) != beta\\r\\n (un-annotated diff-length inference)"); }
    if (last.ping() != 1) { @panic("switch_unannotated_diffstr_xmod_xmod: last.ping() != 1"); }
}
