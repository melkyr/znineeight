// D2 sibling shape: a switch mixing one exact prong with a range prong.
// The exact prong emits its `case`; the range prong is dropped to `else`.
const std = @import("std");

const Color = enum { Red, Green, Blue };

fn mixed(c: Color) i32 {
    return switch (c) {
        Color.Blue => 50,
        Color.Red...Color.Green => 60,
        else => 70,
    };
}

pub fn main() void {
    std.io.print("mixed {d} {d} {d}\n", .{ mixed(Color.Red), mixed(Color.Green), mixed(Color.Blue) });
}
