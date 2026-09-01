pub const Inner = struct { x: u32 };

pub const Item = struct {
    key: []const u8,
    value: ?*Inner,
};
