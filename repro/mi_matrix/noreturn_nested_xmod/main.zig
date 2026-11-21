// noreturn_nested_xmod — A19 value-position fixture (nested if/switch and
// return operand). A noreturn-valued outer if_expr whose then-arm is itself a
// noreturn if_expr, plus a noreturn if_expr/switch_expr as the operand of an
// outer `return`.
// Contract (GREEN): compiles + runs, prints "1\n2\n3\n10\n20\n".
const std = @import("std");

fn viaNested(c: bool, d: bool) i32 {
    const x = if (c) (if (d) return 1 else return 2) else return 3;
    _ = x;
}

fn viaReturnIf(c: bool) i32 {
    return if (c) return 10 else return 11;
}

fn viaReturnSwitch(x: i32) i32 {
    return switch (x) {
        0 => return 20,
        else => return 21,
    };
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaNested(true, true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaNested(true, false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaNested(false, true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaReturnIf(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaReturnSwitch(0)));
    std.io.writeByte('\n');
}
