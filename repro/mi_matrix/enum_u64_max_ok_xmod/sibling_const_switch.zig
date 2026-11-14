// D13 sibling probe: a module-scope const enum value at u64 max used in a
// switch (const-init + emission path).
const std = @import("std");

const E = enum(u64) { A = 18446744073709551615 };
const K = E.A;

pub fn main() void {
    var r: i32 = 0;
    switch (K) {
        E.A => {
            r = 7;
        },
        else => {
            r = 9;
        },
    }
    std.io.printInt(r);
    std.io.writeByte('\n');
}
