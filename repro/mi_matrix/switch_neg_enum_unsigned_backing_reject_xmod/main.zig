// switch_neg_enum_unsigned_backing_reject_xmod — a negative discriminant on an
// unsigned enum backing. Zig 0.17.1 rejects it:
//   error: type 'u32' cannot represent integer value '-1'
// Z98 must cleanly reject it (rc 2, no emitted binary) with the same
// diagnostic family instead of accepting or truncating the value.
const std = @import("std");

const E = enum(u32) { A = -1 };

pub fn main() void {
    const x: E = .A;
    var r: i32 = 0;
    switch (x) {
        .A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
