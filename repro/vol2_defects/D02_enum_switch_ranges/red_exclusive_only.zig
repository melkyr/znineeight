// D2 sibling shape: an exclusive-range-only enum switch.
const std = @import("std");

const Color = enum { Red, Green, Blue };

fn excl(c: Color) i32 {
    return switch (c) {
        Color.Red..Color.Blue => 30,
        else => 40,
    };
}

pub fn main() void {
    std.io.print("excl {d} {d} {d}\n", .{ excl(Color.Red), excl(Color.Green), excl(Color.Blue) });
}
