pub const Data = union {
    Int: i32,
    Str: []const u8,
};
pub const Item = struct { tag: u8, data: Data };
pub const Holder = struct { name: []const u8, val: i32 };
