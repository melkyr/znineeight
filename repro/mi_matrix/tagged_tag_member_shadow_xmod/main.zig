const std = @import("std");

const U = union(enum) {
    tag: i32,
    other: f64,
};

var g: U = U{ .tag = @intCast(i32, 9) };

fn ptrParam(p: *U) bool {
    return p.tag == .tag;
}

pub fn main() void {
    var u: U = U{ .tag = @intCast(i32, 5) };
    std.io.printInt(@intCast(i32, u.tag));
    std.io.writeByte(' ');
    if (u.tag == .tag) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(' ');
    if (u.tag == .other) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(' ');
    switch (u.tag) {
        .tag => std.io.printInt(1),
        .other => std.io.printInt(2),
        else => std.io.printInt(9),
    }
    std.io.writeByte(' ');
    var p: *U = &u;
    std.io.printInt(@intCast(i32, p.tag));
    std.io.writeByte(' ');
    if (ptrParam(p)) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(' ');
    u.tag = 1;
    std.io.printInt(@intCast(i32, u.tag));
    std.io.writeByte(' ');
    if (g.tag == .tag) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte('\n');
}
