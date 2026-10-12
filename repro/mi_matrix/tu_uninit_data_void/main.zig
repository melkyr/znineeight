const Tag = enum { Nil, Int };
const Data = union {
    Int: i32,
};
const Value = struct {
    tag: Tag,
    data: Data,
};
fn make_nil() Value {
    var v: Value = undefined;
    v.tag = Tag.Nil;
    return v;
}
fn copy_val(dst: *Value, src: Value) void {
    dst.* = src;
}
pub fn main() void {
    var v = make_nil();
    var v2: Value = undefined;
    copy_val(&v2, v);
}
