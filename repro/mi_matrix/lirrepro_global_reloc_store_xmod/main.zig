// lirrepro_global_reloc_store_xmod — load_global-alias relocation repro (R-2,
// single-module direct STORE order; LIROPTPASS AMENDMENT 3).
// Theory under test (T4d review M-1): a register-only PURE def computed from a
// load_global-alias temp of `g` whose single textual use is separated from a
// DIRECT store_global write to `g` must NOT be re-materialized at the consumer
// slot (it would re-read the post-store `g` = wrong value).
// GREEN (snapshot contract, byte-exact): "5 100\n105\n" —
//   t = g + 5 read when the var statement executes (g==0 -> 5);
//   g = 100 (direct store_global strictly between t's def and its use);
//   print t -> 5 (a relocation of the g+5 read past the store would print 105);
//   print g -> 100;
//   sink = g + 5 executed after the store -> 105; print sink -> 105.
const std = @import("std");

var g: i32 = 0;
var sink: i32 = 0;

pub fn main() void {
    var t = g + 5;
    g = 100;
    std.io.printInt(t);
    std.io.writeByte(' ');
    std.io.printInt(g);
    std.io.writeByte('\n');
    sink = g + 5;
    std.io.printInt(sink);
    std.io.writeByte('\n');
}
