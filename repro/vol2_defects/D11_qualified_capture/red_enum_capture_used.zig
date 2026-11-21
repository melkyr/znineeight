// D11 bundled sibling (FE): a USED capture on an enum switch (shorthand and
// qualified spellings). Sema registered no local for the capture (the enum
// branch of the case-item resolution never filled `enum_value_table`), so the
// use rejected `error[20]` at the use site.
const std = @import("std");

const Color = enum { red, green, blue };

fn show(c: Color) i32 {
    std.io.print("c={}\n", .{c});
    return 1;
}

fn shorthand(c: Color) i32 {
    return switch (c) {
        .red => |v| show(v),
        else => 0,
    };
}

fn qualified(c: Color) i32 {
    return switch (c) {
        Color.green => |v| show(v),
        else => 0,
    };
}

pub fn main() void {
    std.io.print("{} {}\n", .{ shorthand(Color.red), qualified(Color.green) });
}
