// lirrepro_global_reloc_xmod_xmod — load_global-alias relocation repro (R-3,
// CROSS-MODULE; LIROPTPASS AMENDMENT 3). The global is `pub var g` owned by
// types.zig and read/written from the importing main.zig module, exercising the
// load_global-alias path at module boundaries (extern header decl in main's
// header, single definition in types) and probing whether any OTHER bug arises
// (header/extern/def emission interacting with a relocation).
// GREEN (snapshot contract, byte-exact): "5 1 1\n205 300\n" —
//   t = types.g + 5 read when the var statement executes (g==0 -> 5);
//   types.bumpAndGet() (cross-module call) -> g==1, discarded;
//   print t -> 5 (relocation past the call would print 6);
//   print types.g -> 1; print types.read() -> 1;
//   types.g = 200 (cross-module direct store);
//   u = types.g + 5 -> 205 (snapshot);
//   types.g = 300 (direct store between u's def and use);
//   print u -> 205 (relocation would print 305); print types.read() -> 300.
const std = @import("std");
const types = @import("types");

pub fn main() void {
    var t = types.g + 5;
    _ = types.bumpAndGet();
    std.io.printInt(t);
    std.io.writeByte(' ');
    std.io.printInt(types.g);
    std.io.writeByte(' ');
    std.io.printInt(types.read());
    std.io.writeByte('\n');
    types.g = 200;
    var u = types.g + 5;
    types.g = 300;
    std.io.printInt(u);
    std.io.writeByte(' ');
    std.io.printInt(types.read());
    std.io.writeByte('\n');
}
