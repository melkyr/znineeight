const t = @import("types.zig");
const Tag = enum { Int, Str };
const Data = union {
    Int: i32,
    Str: []const u8,
};
const Value = struct {
    tag: Tag,
    data: Data,
};

pub fn main() void {
    var arena_buf: [64]u8 = undefined;
    const ptr = @ptrCast(*Value, &arena_buf[0]);
    ptr.tag = Tag.Int;
    ptr.data.Int = 42;
}
