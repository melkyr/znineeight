// Off-corpus mutable-for fixture (Task 4 fix round 1, coverage 5): `|*f|` over
// a `[]fn(u32)u32` slice. The element type is a function pointer, so the
// capture is a pointer-to-fn-pointer (`FP*`). Mutating the slot (`f.* = add2`)
// and calling through the slice afterwards proves the capture aliases the
// table.
const std = @import("std");

fn add1(x: u32) u32 {
    return x + 1;
}

fn add2(x: u32) u32 {
    return x + 2;
}

pub fn main() void {
    var table: [2]fn(u32) u32 = [2]fn(u32) u32{ add1, add1 };
    const s: []fn(u32) u32 = table[0..];
    for (s, 0..) |*f, i| {
        if (i == 0) {
            f.* = add2;
        }
    }
    var out: u32 = 0;
    for (s) |f| {
        out += f(10);
    }
    std.io.printInt(@intCast(i32, out));
    std.io.writeByte('\n');
}
