// D3 control: matching `switch` with a mandatory `else`; and an `if` statement
// with no `else` (legal).
const std = @import("std");

fn pickElse(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
        else => -1,
    };
}

pub fn main() void {
    std.io.print("matched_else={}\n", .{pickElse(1)});
    std.io.print("unmatched_else={}\n", .{pickElse(7)});
    var flag: bool = false;
    if (!flag) std.io.print("if_no_else_statement=ok\n", .{});
}
