// lirrepro_global_reloc_call_xmod — load_global-alias relocation repro (R-1,
// single-module CALL-order; LIROPTPASS AMENDMENT 3).
// Theory under test (T4d review M-1): a register-only PURE def computed from a
// load_global-alias temp of `g` whose single textual use is separated from an
// ORDERED write to `g` by a CALL must NOT be re-materialized at the consumer
// slot (it would re-read the post-write `g` = wrong value).
// GREEN (snapshot contract, byte-exact): "5\n2\n2\n8\n3\n" —
//   t = g + 5 read when the var statement executes (g==0 -> 5);
//   bumpAndGet() x1 -> g==1 (result discarded);
//   print t -> 5 (a relocation of the g+5 read past the call would print 6);
//   print bumpAndGet() -> g becomes 2, returns 2;
//   print g -> 2;
//   u = t + bumpAndGet(): t reloads 5, call -> g==3 returns 3, u==8;
//   print u -> 8; print g -> 3.
const std = @import("std");

var g: i32 = 0;

fn bumpAndGet() i32 {
    g = g + 1;
    return g;
}

pub fn main() void {
    var t = g + 5;
    _ = bumpAndGet();
    std.io.printInt(t);
    std.io.writeByte('\n');
    std.io.printInt(bumpAndGet());
    std.io.writeByte('\n');
    std.io.printInt(g);
    std.io.writeByte('\n');
    var u = t + bumpAndGet();
    std.io.printInt(u);
    std.io.writeByte('\n');
    std.io.printInt(g);
    std.io.writeByte('\n');
}
