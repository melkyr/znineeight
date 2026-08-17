const std = @import("std");

fn c89EmitterInit(a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32) i32 {
    return a + b + c + d + e + f + g + h + i;
}

pub fn main() void {
    var result: i32 = c89EmitterInit(
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
    );
    std.io.printInt(result);
}
