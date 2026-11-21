const pal = @import("../pal.zig");

const U = union(enum) {
    jump: u32,
    assign: struct { dst: u32, src: u32 },
    ret: void,
};

pub fn main() void {
    pal.initArgs(@intCast(i32, 0), undefined);
    var u1 = U{ .jump = @intCast(u32, 42) };
    var tag: u32 = @intCast(u32, 0);
    switch (u1) {
        .jump => |val| {
            if (val == @intCast(u32, 42)) { tag = @intCast(u32, 1); }
        },
        .assign => |a| {
            if (a.dst == @intCast(u32, 0)) { tag = @intCast(u32, 2); }
        },
        .ret => {
            tag = @intCast(u32, 3);
        },
        else => {},
    }
    if (tag == @intCast(u32, 1)) {
        pal.stdout_write("ok\n");
    }
}
