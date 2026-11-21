const std = @import("std.zig");
const mod_a = @import("mod_a.zig");

const Kind = enum(u16) { plus, minus, star };

fn b_pick(k: Kind) u32 {
    var r: u32 = 0;
    switch (k) {
        .plus => r = 1,
        .minus => r = 2,
        .star => r = 3,
        else => {},
    }
    return r;
}

pub fn main() void {
    std.io.printInt(mod_a.pick(mod_a.Kind.star));
    std.io.print("\n");
    std.io.printInt(b_pick(Kind.minus));
    std.io.print("\n");
    var i: i32 = 0;
    while (i < @intCast(i32, 3)) {
        if (i == 0) {
            switch (Kind.plus) {
                Kind.plus => std.io.printInt(1),
                Kind.minus => std.io.printInt(2),
                Kind.star => std.io.printInt(3),
                else => {},
            }
        } else if (i == 1) {
            switch (Kind.minus) {
                Kind.plus => std.io.printInt(1),
                Kind.minus => std.io.printInt(2),
                Kind.star => std.io.printInt(3),
                else => {},
            }
        } else {
            switch (Kind.star) {
                Kind.plus => std.io.printInt(1),
                Kind.minus => std.io.printInt(2),
                Kind.star => std.io.printInt(3),
                else => {},
            }
        }
        i = i + @intCast(i32, 1);
    }
    std.io.print("\n");
    std.io.printInt(@intCast(i32, @enumToInt(Kind.star)));
    std.io.print("\n");
}
