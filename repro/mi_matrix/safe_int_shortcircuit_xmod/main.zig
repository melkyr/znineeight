// safe_int_shortcircuit_xmod — `-fsafe` short-circuit guard CORRECTNESS control
// (A6F). These boundary operations are all representable and MUST NOT trap; the
// signed guards' `MAX-b` / `MIN+b` sub-terms would themselves overflow (C UB)
// if evaluated unconditionally, so the emitter must preserve `&&`/`||`
// short-circuit from the operands rather than a precomputed `cond` temp.
//
// Expected under `-fsafe`, `-ffast`, and PRE: rc 0, `-2147483648 -1 0 1`.
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn sub(a: i32, b: i32) i32 {
    return a - b;
}

fn mul(a: i32, b: i32) i32 {
    return a * b;
}

pub fn main() void {
    var z: i32 = 0;
    var mn: i32 = -2147483647 - 1;
    var p: i32 = 1;
    var r1: i32 = add(z, mn);
    var r2: i32 = sub(z, p);
    var r3: i32 = mul(z, mn);
    var ua: u32 = 0;
    var ub: u32 = 1;
    var r4: u32 = ua + ub;
    std.io.printInt(r1);
    std.io.writeByte(' ');
    std.io.printInt(r2);
    std.io.writeByte(' ');
    std.io.printInt(r3);
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, r4));
    std.io.writeByte('\n');
}
