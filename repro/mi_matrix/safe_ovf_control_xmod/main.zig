// A15 fixture (C89-AHEAD): no-false-trap CONTROL.
//
// All of these operations are representable and MUST NOT trap under `-fsafe`:
// in-range signed add/sub/mul, unary negate, and the same-width mixed-sign
// `i32 MIN + u32 1` case (resolves to i32, -2147483647). The guard is a
// runtime predicate, so both the wrapped-value op and the flag helper must
// agree on the (non-)overflow boundary.
//
// Expected under `-fsafe`, `-ffast`, and PRE: rc 0,
// `1024 976 576 5` and `-2147483647`.
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
    var a: i32 = 1000;
    var b: i32 = 24;
    var r1: i32 = add(a, b);
    var r2: i32 = sub(a, b);
    var r3: i32 = mul(b, b);
    var n: i32 = -5;
    var r4: i32 = -n;
    std.io.printInt(r1);
    std.io.writeByte(32);
    std.io.printInt(r2);
    std.io.writeByte(32);
    std.io.printInt(r3);
    std.io.writeByte(32);
    std.io.printInt(r4);
    std.io.writeByte(10);
    var mn: i32 = -2147483647 - 1;
    var one: u32 = 1;
    var rm: i32 = mn + one;
    std.io.printInt(rm);
    std.io.writeByte(10);
}
