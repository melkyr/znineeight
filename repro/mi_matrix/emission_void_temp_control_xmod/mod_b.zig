const mod_a = @import("mod_a.zig");
const TokenKind = mod_a.TokenKind;
const TokenValue = mod_a.TokenValue;
const Token = mod_a.Token;

pub fn inWhile() u32 {
    var i: u32 = 0;
    var acc: u32 = 0;
    while (i < 2) : (i += 1) {
        var t = mod_a.makeToken(TokenKind.eof, i, .{ .none = {} });
        acc = acc + t.start;
    }
    return acc;
}

pub fn viaFnPtr() u32 {
    var f: fn (TokenKind, u32, TokenValue) Token = mod_a.makeToken;
    var t = f(TokenKind.eof, 0, .{ .none = {} });
    return t.start;
}
