const t = @import("types.zig");
pub fn main() void {
    var arena_buf: [64]u8 = undefined;
    const ptr = @ptrCast(*t.Data, &arena_buf[0]);
    ptr.id = 42;
    ptr.name = "ok";
}
