pub const Item = struct {
    key: []const u8,
    value: i32,
};

pub const MyUnion = union(enum) {
    List: []Item,
    Empty,
};
