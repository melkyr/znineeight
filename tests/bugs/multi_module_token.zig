pub const Token = union(enum) {
    LParen: void,
    RParen: void,
    Int: i64,
    Symbol: []const u8,
    Eof: void,
};
