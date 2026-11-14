const Inner = struct { x: u32 };

const Item = struct {
    key: []const u8,
    value: ?*Inner,
};

pub fn main() void {
    var inner: Inner = Inner{ .x = 42 };
    var item: Item = Item{ .key = "test", .value = &inner };
    if (item.value) |v| {
        _ = v.*.x;
    }
}
