// switch_bool_neg_reject_xmod — a bare negative integer case item on a `bool`
// condition. Z98 currently accepts it and emits the invalid C label
// `case 18446744073709551615:`. Zig 0.17.1 rejects the type mismatch; Z98 must
// cleanly reject it with the existing unsigned-negative diagnostic family while
// keeping `true`/`false` and integer `0`/`1` accepted.
//
// Contract: rc 2, no `.c`, `error[3062]`
// `type 'bool' cannot represent integer value '-1'`.
const std = @import("std");

pub fn main() void {
    const b: bool = true;
    var r: i32 = 0;
    switch (b) {
        -1 => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
