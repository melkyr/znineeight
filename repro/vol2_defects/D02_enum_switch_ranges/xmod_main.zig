// D2 cross-module RED: enum type imported from colors.zig, ranges switched in
// main.zig.
const std = @import("std");
const colors = @import("colors.zig");

fn incl(c: colors.Color) i32 {
    return switch (c) {
        colors.Color.Red...colors.Color.Green => 10,
        else => 20,
    };
}

fn excl(c: colors.Color) i32 {
    return switch (c) {
        colors.Color.Red..colors.Color.Blue => 30,
        else => 40,
    };
}

pub fn main() void {
    std.io.print("incl {d} {d} {d}\n", .{ incl(colors.Color.Red), incl(colors.Color.Green), incl(colors.Color.Blue) });
    std.io.print("excl {d} {d} {d}\n", .{ excl(colors.Color.Red), excl(colors.Color.Green), excl(colors.Color.Blue) });
}
