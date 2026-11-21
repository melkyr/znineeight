const lib = @import("lib.zig");

pub fn main() void {
    var inner: lib.Inner = lib.Inner{ .x = 42 };
    var item: lib.Item = lib.Item{ .key = "test", .value = &inner };
    if (item.value) |v| {
        _ = v.*.x;
    }
}
