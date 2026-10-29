// stdlib_fold_i32_ok_xmod — STDLIB std_fold (per-type fold) i32 fixture.
//
// std.fold.foldI32(xs, acc, f) walks the slice in order and applies
// `acc = f(acc, x)` through a function-pointer combiner. The combiner is
// subtraction (a - x), so the order and the accumulator direction are pinned.
//
// GREEN (contract): deterministic byte-exact stdout `94\n` (RUNRC=0).
const std = @import("std");

fn step(a: i32, x: i32) i32 {
    return a - x;
}

pub fn main() void {
    var xs = [_]i32{ 1, 2, 3 };
    var r = std.fold.foldI32(xs[0..], 100, step);
    std.io.printInt(r);
    std.io.writeByte('\n');
}
