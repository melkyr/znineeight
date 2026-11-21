const std = @import("std.zig");
const mod_a = @import("mod_a.zig");

const U = union(enum) {
    jump: u32,
    ret: void,
};

pub fn main() void {
    var ua = mod_a.make_jump();
    switch (ua) {
        .jump => |val| {
            std.io.printInt(val);
            std.io.print("\n");
        },
        .ret => {
            std.io.printInt(@intCast(u32, 0));
            std.io.print("\n");
        },
        else => {},
    }

    var ub = U{ .jump = @intCast(u32, 9) };
    var tag: u32 = @intCast(u32, 0);
    switch (ub) {
        .jump => |v| {
            tag = @intCast(u32, 1);
        },
        .ret => {
            tag = @intCast(u32, 2);
        },
        else => {},
    }
    std.io.printInt(tag);
    std.io.print("\n");

    var uc = U{ .jump = @intCast(u32, 5) };
    var arr: [2]u32 = [2]u32{ @intCast(u32, 10), @intCast(u32, 20) };
    var sum: u32 = @intCast(u32, 0);
    switch (uc) {
        .jump => |d| {
            if (d < @intCast(u32, 10)) {
                for (arr) |x| {
                    sum += d + x;
                }
            }
        },
        .ret => {},
        else => {},
    }
    std.io.printInt(sum);
    std.io.print("\n");
}
