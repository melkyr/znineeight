pub const TokenKind = enum(u8) { eof, ident, lparen, rparen };

pub const TokenValue = union(enum) {
    none: void,
    ident: struct { name: []const u8 },
};

pub const Token = struct {
    kind: TokenKind,
    start: u32,
    value: TokenValue,
};
