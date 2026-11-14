const mod_a = @import("mod_a.zig");
const TokenKind = mod_a.TokenKind;

fn kindNum(kind: TokenKind) i32 {
    return switch (kind) {
        .eof => 0,
        .ident => 1,
        .lparen => 2,
        .rparen => 3,
        else => unreachable,
    };
}

pub const Lexer = struct {
    pos: u32,
};

pub fn nextToken(self: Lexer) i32 {
    return kindNum(.eof) + @intCast(i32, self.pos);
}
