pub const Tag = enum { A, B, C };

pub const Data = union {
    I: i64,
    S: []const u8,
    F: f64,
};

pub const Value = struct {
    tag: Tag,
    data: Data,
};

pub fn makeValue(n: i32) Value {
    return Value{ .tag = Tag.A, .data = Data{ .I = @intCast(i64, n) } };
}
