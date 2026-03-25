pub const Token = union(enum) {
    Eof: void,
    Number: i64,
};

pub fn set_union_ptr(t: *Token) void {
    t.* = .Eof;
}

pub fn main() void {
    var t: Token = Token{ .Number = @intCast(i64, 0) };
    set_union_ptr(&t);
}
