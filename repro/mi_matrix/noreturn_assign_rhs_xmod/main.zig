// noreturn_assign_rhs_xmod — A19 value-position fixture (assignment RHS).
// A noreturn-valued if_expr / switch_expr on the right-hand side of a plain
// assignment: the arms emit their own terminators and the store is dead, so
// the assignment must not consume a noreturn-typed result temp.
// Contract (GREEN): compiles + runs, prints "1\n2\n10\n11\n".
const std = @import("std");

fn viaAssignIf(c: bool) i32 {
    var x: i32 = 0;
    x = if (c) return 1 else return 2;
    _ = x;
}

fn viaAssignSwitch(x: i32) i32 {
    var y: i32 = 0;
    y = switch (x) {
        0 => return 10,
        else => return 11,
    };
    _ = y;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaAssignIf(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaAssignIf(false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaAssignSwitch(0)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaAssignSwitch(1)));
    std.io.writeByte('\n');
}
