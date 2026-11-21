// crossmod_pubvar_xmod — RED fixture (cross-module pub var; single storage).
// Feature: a module-scope `pub var` imported and written from another module
//   must refer to ONE storage cell (emitted C: extern decl in the importing
//   module's header, one definition in the owning module).
// RED today (per upstream P1-2 note): the extern header decl is missing or
//   duplicated -> runtime-wrong (0 0 / 7 0) or link failure. RECORD ACTUAL.
// GREEN (contract): "7 7\n" — importer write visible to owner's read().
const std = @import("std");
const other = @import("other");

pub fn main() void {
    other.shared = 7;
    std.io.printInt(other.shared);
    std.io.writeByte(' ');
    std.io.printInt(other.read());
    std.io.writeByte('\n');
}
