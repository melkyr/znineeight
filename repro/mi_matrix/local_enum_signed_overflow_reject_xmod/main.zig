// local_enum_signed_overflow_reject_xmod — a function-local enum whose
// discriminant does not fit its signed backing (`enum(i8) { A = 300 }`). The
// local/inline enum path must reject it with the enum-backing-range error
// instead of accepting the out-of-range value.
//
// Contract: rc 2, no emitted binary.
const std = @import("std");

pub fn main() void {
    const E = enum(i8) { A = 300 };
    const x: E = .A;
    var r: i32 = 0;
    switch (x) {
        .A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
