// D2 control: integer switch ranges (inclusive and exclusive) emit real case
// labels and match correctly.
const std = @import("std");

fn incl(x: i32) i32 {
    return switch (x) {
        1...5 => 10,
        else => 20,
    };
}

fn excl(x: i32) i32 {
    return switch (x) {
        1..5 => 30,
        else => 40,
    };
}

pub fn main() void {
    std.io.print("incl {d} {d} {d}\n", .{ incl(1), incl(5), incl(6) });
    std.io.print("excl {d} {d} {d}\n", .{ excl(1), excl(4), excl(5) });
}
