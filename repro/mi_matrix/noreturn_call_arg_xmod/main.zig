// noreturn_call_arg_xmod — A19 value-position fixture (call argument).
// A noreturn-valued if_expr / switch_expr passed as a call argument: the arms
// return before the call, so the call is unreachable and must not consume a
// noreturn-typed argument temp.
// Contract (GREEN): compiles + runs, prints "1\n2\n10\n11\n".
const std = @import("std");

fn sink(v: i32) i32 {
    return v + 100;
}

fn viaCallIf(c: bool) i32 {
    return sink(if (c) return 1 else return 2);
}

fn viaCallSwitch(x: i32) i32 {
    return sink(switch (x) {
        0 => return 10,
        else => return 11,
    });
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaCallIf(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaCallIf(false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaCallSwitch(0)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaCallSwitch(1)));
    std.io.writeByte('\n');
}
