// safe_int_compound_add_loop_xmod — `-fsafe` compound loop-continue CONTROL
// (A6F). Exercises the second compound path (`while (...) : (i += 1)`).
//
// The loop-continue compound node has no semantic resolved type, so the
// lowering default (`TYPE_U32`) must NOT be used as the guard's result type or
// a negative signed counter false-traps: `i = -1` read as unsigned is
// `0xFFFFFFFF > 0xFFFFFFFF - 1`. A6F bounds the compound guard by the LHS
// type instead, so this runs clean.
//
// Expected under `-fsafe`, `-ffast`, and PRE: rc 0, `-2`.
const std = @import("std");

pub fn main() void {
    var i: i32 = -2;
    var sum: i32 = 0;
    while (i < 2) : (i += 1) {
        sum += i;
    }
    std.io.printInt(sum);
    std.io.writeByte('\n');
}
