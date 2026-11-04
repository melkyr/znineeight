// local_enum_neg_unsigned_backing_reject_xmod — a function-local enum with a
// negative discriminant on an unsigned backing. The local/inline enum path
// must apply the same fit rule as the module gate:
//   error[3062]: type 'u8' cannot represent integer value '-1'
// Clean reject: rc 2, no emitted binary.
const std = @import("std");

pub fn main() void {
    const E = enum(u8) { A = -1 };
    const x: E = .A;
    var r: i32 = 0;
    switch (x) {
        .A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
