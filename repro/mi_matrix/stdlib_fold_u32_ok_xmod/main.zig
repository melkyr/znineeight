// stdlib_fold_u32_ok_xmod — STDLIB std_fold (per-type fold) u32 fixture.
//
// std.fold.foldU32(xs, acc, f) walks the slice in order and applies
// `acc = f(acc, x)` through a function-pointer combiner (the proven indirect
// call path). The combiner here is NON-COMMUTATIVE (a * 10 + x), so a wrong
// iteration order or a wrong accumulator direction changes the result.
//
// GREEN (contract): deterministic byte-exact stdout `1234\n` (RUNRC=0).
const std = @import("std");

fn step(a: u32, x: u32) u32 {
    return a * 10 + x;
}

pub fn main() void {
    var xs = [_]u32{ 1, 2, 3, 4 };
    var r = std.fold.foldU32(xs[0..], 0, step);
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
