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

pub fn compute(n: i32) i32 {
    var v = Value{ .tag = Tag.A, .data = Data{ .I = @intCast(i64, n) } };
    var s = @sizeOf(Value);
    var a = @alignOf(Value);
    var r: i32 = 0;
    r = r + @intCast(i32, s);
    r = r + @intCast(i32, a);
    return r;
}
