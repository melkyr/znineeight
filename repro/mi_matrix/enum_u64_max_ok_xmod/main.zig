// enum_u64_max_ok_xmod — Phase 3.5 D13 repro.
//
// A legal `enum(u64)` discriminant at the u64 maximum
// (`18446744073709551615`) must be accepted, lowered and compared correctly.
// Pre-fix the compiler rejects it with the explicit `error[3000]` storage
// limitation (member values are held in an i64 slot).
//
// GREEN (post-fix): dump rc=0, runtime switch reads the value, stdout `7\n`,
// rc 0.
const std = @import("std");

const E = enum(u64) { A = 18446744073709551615 };

pub fn main() void {
    var x: E = E.A;
    var r: i32 = 0;
    switch (x) {
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
