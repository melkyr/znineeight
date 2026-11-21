const std = @import("std");

@cInclude("zig_runtime.h");

fn add(a: i32, b: i32) i32 { return a + b; }
fn sub(a: i32, b: i32) i32 { return a - b; }

fn getOp(kind: u8) fn(i32, i32) i32 {
    if (kind == '+') { return add; }
    else { return sub; }
}

pub fn main() void {
    const op_plus = getOp('+');
    const res1 = op_plus(10, 5);
    std.io.print("10 + 5 = ");
    std.io.printInt(res1);
    std.io.print("\n");

    const op_minus = getOp('-');
    const res2 = op_minus(10, 5);
    std.io.print("10 - 5 = ");
    std.io.printInt(res2);
    std.io.print("\n");
}
