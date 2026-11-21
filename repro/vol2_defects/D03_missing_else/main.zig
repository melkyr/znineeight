// D3 in-module RED: a `switch` with no `else` is accepted; an unmatched value
// reads an uninitialized result temp (garbage, provenance-dependent).
// Silent wrong value: rc 0.
const std = @import("std");

fn pickNoElse(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
    };
}

fn pickElse(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
        else => -1,
    };
}

pub fn main() void {
    std.io.print("matched_no_else={}\n", .{pickNoElse(1)});
    std.io.print("unmatched_no_else={}\n", .{pickNoElse(7)});
    std.io.print("matched_else={}\n", .{pickElse(1)});
    std.io.print("unmatched_else={}\n", .{pickElse(7)});

    var flag: bool = false;
    if (!flag) std.io.print("if_no_else_statement=ok\n", .{});
}
