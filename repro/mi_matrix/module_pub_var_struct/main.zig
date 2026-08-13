const std = @import("std.zig");

const Writer = struct {
    tag: i32,
};

pub var out: Writer = undefined;

pub fn main() void {
    out.tag = 7;
    std.io.printInt(out.tag);
}
