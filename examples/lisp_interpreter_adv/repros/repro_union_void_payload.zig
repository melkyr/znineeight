pub const Token = union(enum) {
    Eof,
    Int: i64,
};

pub fn test_union_void_payload() Token {
    return .Eof;
}

pub fn main() void {
    _ = test_union_void_payload();
}
