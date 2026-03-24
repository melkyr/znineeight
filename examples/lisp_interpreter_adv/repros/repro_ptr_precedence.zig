pub const Value = struct {
    tag: i32,
};

pub fn test_ptr_precedence(v: *Value) void {
    v.tag = 42;
}

pub fn main() void {
    var v = Value{ .tag = 0 };
    test_ptr_precedence(&v);
}
