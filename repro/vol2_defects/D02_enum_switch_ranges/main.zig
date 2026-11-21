// D2 in-module RED: enum `switch` range prongs (inclusive `a...b` and
// exclusive `a..b`) emit no `case` labels, so every value takes `else`.
// Silent wrong code: rc 0, wrong stdout.
const std = @import("std");

const Color = enum { Red, Green, Blue };

fn incl(c: Color) i32 {
    return switch (c) {
        Color.Red...Color.Green => 10,
        else => 20,
    };
}

fn excl(c: Color) i32 {
    return switch (c) {
        Color.Red..Color.Blue => 30,
        else => 40,
    };
}

fn mixed(c: Color) i32 {
    return switch (c) {
        Color.Blue => 50,
        Color.Red...Color.Green => 60,
        else => 70,
    };
}

pub fn main() void {
    std.io.print("incl {d} {d} {d}\n", .{ incl(Color.Red), incl(Color.Green), incl(Color.Blue) });
    std.io.print("excl {d} {d} {d}\n", .{ excl(Color.Red), excl(Color.Green), excl(Color.Blue) });
    std.io.print("mixed {d} {d} {d}\n", .{ mixed(Color.Red), mixed(Color.Green), mixed(Color.Blue) });
}
