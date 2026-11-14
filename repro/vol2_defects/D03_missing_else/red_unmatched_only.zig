// D3 sibling shape: only the unmatched-value path, to show the uninitialized
// result temp in isolation.
const std = @import("std");

fn pickNoElse(x: i32) i32 {
    return switch (x) {
        1 => 100,
        2 => 200,
    };
}

pub fn main() void {
    std.io.print("unmatched_no_else={}\n", .{pickNoElse(7)});
}
