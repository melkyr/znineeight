// D13 sibling probe: signed enum with a negative member (must stay unchanged).
const std = @import("std");

const E = enum(i64) { A = -1, B = 2 };

pub fn main() void {
    var x: E = E.A;
    var r: i32 = 0;
    switch (x) {
        E.A => {
            r = 1;
        },
        E.B => {
            r = 2;
        },
        else => {
            r = 9;
        },
    }
    std.io.printInt(r);
    std.io.writeByte('\n');
}
