// prune_globaltype_owner_xmod — regression for module-prune type deps.
//
// `holder` is reachable (main calls holder.rd) and defines a by-value module
// global `g` whose type `Thing` is owned by `types`. No reachable function
// ever names `Thing`, so the value-reference scan alone yields no holder->types
// edge and `types` is pruned; but holder.h/holder.c still emit
// `zT_<hash>_Thing zG_<hash>_g;`, requiring `Thing`'s definition from types.h.
//
// RED (pre-fix): `types_*.c/.h` absent -> gcc
//   "error: storage size of 'zG_..._g' isn't known".
// GREEN: `types` emitted, holder.h includes types.h, gcc/link/run rc=0 -> "9".
const holder = @import("holder.zig");
const std = @import("std");

pub fn main() void {
    std.io.printInt(holder.rd());
}
