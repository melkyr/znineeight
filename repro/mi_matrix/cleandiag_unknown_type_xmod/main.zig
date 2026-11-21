// cleandiag_unknown_type_xmod — CLEAN-DIAG fixture (unknown type in var decl).
// Feature: unknown type annotations get a clean "unknown type" error, not the
//   misleading void-fallback ("cannot declare variable of type void", R7 class).
// RED today: error[3000]: cannot declare variable of type void.
// GREEN (contract): dump rc=2, 0 .c, error[3000]: unknown type in variable
//   declaration (and NO "cannot declare variable of type void").
const std = @import("std");

pub fn main() void {
    var a: bogusfoo = 1;
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte('\n');
}
