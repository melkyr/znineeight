const Tag = enum { Nil, Int, Str };
const Data = union {
    Int: i32,
    Str: []const u8,
};
const Value = struct {
    tag: Tag,
    data: Data,
};
fn make_int(n: i32) Value {
    var v: Value = undefined;
    v.tag = Tag.Int;
    v.data.Int = n;
    return v;
}
pub fn main() void {
    var buf: [32]u8 = undefined;
    var v = make_int(42);
    const ptr = @ptrCast(*Value, &buf[0]);
    ptr.* = v;
}
