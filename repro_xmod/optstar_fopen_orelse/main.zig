const lib = @import("lib.zig");

pub fn main() void {
    var path: [*]const u8 = @ptrCast([*]const u8, "test");
    var x = lib.fopen(path, path) orelse return;
    _ = x;
}
