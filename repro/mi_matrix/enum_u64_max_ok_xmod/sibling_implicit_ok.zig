// D13 sibling probe: the implicit successor after u64_max - 1 is u64 max and
// must be accepted post-fix.
const std = @import("std");

const E = enum(u64) { A = 18446744073709551614, B };

pub fn main() void {
    var x: E = E.B;
    var r: i32 = 0;
    switch (x) {
        E.B => {
            r = 7;
        },
        else => {
            r = 9;
        },
    }
    std.io.printInt(r);
    std.io.writeByte('\n');
}
