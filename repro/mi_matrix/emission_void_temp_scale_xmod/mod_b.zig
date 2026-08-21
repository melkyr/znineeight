const mod_a = @import("mod_a.zig");
const Token = mod_a.Token;
const TokenKind = mod_a.TokenKind;
const TokenValue = mod_a.TokenValue;

fn makeToken(kind: TokenKind, start: u32, value: TokenValue) Token {
    return .{ .kind = kind, .start = start, .value = value };
}

pub const Lexer = struct {
    pos: u32,
};

pub fn nextToken(self: Lexer) Token {
    return makeToken(TokenKind.eof, self.pos, .{ .none = {} });
}
