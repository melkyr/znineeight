// diag_missing_return_xmod — compile-time diagnostic: missing return.
// Contract (GREEN): a non-void function that can fall off the end is an ERROR
//   (error[3003]); a bare `return;` in a non-void function is an ERROR
//   (error[3003]). dump rc=2, 0 emitted .c.
// RED (today, pre-A7F): silently accepted; fall-off and bare return synthesize
//   a value, emits C and runs.
const std = @import("std");

fn fallOff(x: i32) i32 {
    if (x > 0) {
        return 1;
    }
}

fn bareReturn() i32 {
    return;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, fallOff(1)));
    std.io.writeByte('\n');
}
