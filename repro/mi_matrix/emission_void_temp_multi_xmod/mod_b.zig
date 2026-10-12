const mod_a = @import("mod_a.zig");
const Token = mod_a.Token;
const TokenKind = mod_a.TokenKind;
const TokenValue = mod_a.TokenValue;

fn combine(a: TokenValue, b: TokenValue) Token {
    return .{ .kind = .eof, .start = 0, .value = a };
}

pub const Lexer = struct {
    pos: u32,
};

pub fn nextToken(self: Lexer) Token {
    return combine(.{ .none = {} }, .{ .ident = .{ .name = "x" } });
}
