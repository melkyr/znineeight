// stdlib_fold_usize_ok_xmod — STDLIB std_fold (per-type fold) usize fixture.
//
// std.fold.foldUsize(xs, acc, f) walks the slice in order and applies
// `acc = f(acc, x)` through a function-pointer combiner. The combiner is
// non-commutative (a * 2 + x), so the order and accumulator direction are
// pinned.
//
// GREEN (contract): deterministic byte-exact stdout `118\n` (RUNRC=0).
const std = @import("std");

fn step(a: usize, x: usize) usize {
    return a * 2 + x;
}

pub fn main() void {
    var xs = [_]usize{ 10, 20, 30 };
    var r = std.fold.foldUsize(xs[0..], 1, step);
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
