pub const Token = union(enum) {
    Eof,
    Int: i64,
};

pub fn test_union_void_payload(t: *Token) void {
    t.* = .Eof;
}

pub fn main() void {
    var t: Token = undefined;
    test_union_void_payload(&t);
}
