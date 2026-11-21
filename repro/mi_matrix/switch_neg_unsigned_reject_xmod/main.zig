// switch_neg_unsigned_reject_xmod — negative integer case item on an unsigned
// `u32` condition. Zig 0.17.1 rejects this at compile time:
//   error: type 'u32' cannot represent integer value '-1'
// Z98 must cleanly reject it (rc 2, no emitted binary) instead of accepting it
// and dropping the prong.
const std = @import("std");

pub fn main() void {
    const x: u32 = 1;
    var r: i32 = 0;
    switch (x) {
        -1 => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
