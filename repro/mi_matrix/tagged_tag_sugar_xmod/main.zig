const std = @import("std");
const lib = @import("lib.zig");

var g: lib.Shape = lib.Shape{ .Circle = @intCast(i32, 1) };

fn ptrParam(p: *lib.Shape) bool {
    return p.tag == .Circle;
}

pub fn main() void {
    var s: lib.Shape = lib.Shape{ .Line = @intCast(u32, 5) };
    var p: *lib.Shape = &s;
    if (s.tag == .Line) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag != .Circle) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag == lib.Shape.Line) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (lib.Shape.Line == s.tag) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (.Line == s.tag) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag == lib.Alias.Line) { std.io.printInt(1); } else { std.io.printInt(0); }
    if ((s.tag) == (.Line)) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag > .Circle) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (.Circle < s.tag) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag >= lib.Shape.Line) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag < lib.Shape.Empty) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag <= .Square) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag == .Empty) { std.io.printInt(1); } else { std.io.printInt(0); }
    switch (s.tag) {
        .Circle => std.io.printInt(1),
        .Square => std.io.printInt(2),
        .Empty => std.io.printInt(3),
        .Line => std.io.printInt(4),
        else => std.io.printInt(9),
    }
    switch (s.tag) {
        lib.Shape.Line => std.io.printInt(4),
        else => std.io.printInt(9),
    }
    var n: i32 = switch (s.tag) {
        .Line => @intCast(i32, 40),
        .Circle => @intCast(i32, 10),
        .Square => @intCast(i32, 20),
        .Empty => @intCast(i32, 30),
        else => @intCast(i32, 90),
    };
    std.io.printInt(n);
    switch (s.tag) {
        .Line => |c| { std.io.printInt(c); },
        else => { std.io.printInt(99); },
    }
    switch (s.tag) {
        .Line => {
            switch (s.tag) {
                .Line => std.io.printInt(7),
                else => std.io.printInt(8),
            }
        },
        else => std.io.printInt(9),
    }
    if (p.tag == .Line) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (ptrParam(p)) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s.tag == 3) { std.io.printInt(1); } else { std.io.printInt(0); }
    switch (s.tag) {
        3 => std.io.printInt(5),
        0 => std.io.printInt(6),
        else => std.io.printInt(9),
    }
    std.io.printInt(@intCast(i32, @enumToInt(s.tag)));
    const t = s.tag;
    if (t == 3) { std.io.printInt(1); } else { std.io.printInt(0); }
    var c: lib.Color = lib.Color.Red;
    if (c == .Red) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (c == lib.Color.Green) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (g.tag == .Circle) { std.io.printInt(1); } else { std.io.printInt(0); }
    var s2: lib.Shape = lib.Shape{ .Line = @intCast(u32, 5) };
    var p2: *lib.Shape = &s2;
    p2.tag = 1;
    if (p2.tag == .Square) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (s2.tag == .Square) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte('\n');
}
