// local_enum_pos_ok_xmod — a valid function-local unsigned enum still works
// after the local backing-fit validation.
//
// Contract: `x` is `.A`, so the `.A` prong sets `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

pub fn main() void {
    const E = enum(u8) { A = 1, B = 2 };
    const x: E = .A;
    var r: i32 = 0;
    switch (x) {
        .A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
