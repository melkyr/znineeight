const util = @import("util.zig");

pub const TokenTag = enum {
    LParen,
    RParen,
    Int,
    Symbol,
    Eof,
};

pub const TokenData = union {
    Int: i64,
    Symbol: []const u8,
};

pub const Token = struct {
    tag: TokenTag,
    data: TokenData,
};

pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
};

fn is_whitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn is_digit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn skip_whitespace(self: *Tokenizer) void {
    while (self.pos < self.input.len and is_whitespace(self.input[self.pos])) {
        self.pos += 1;
    }
}

pub fn next_token(self: *Tokenizer) !Token {
    skip_whitespace(self);
    if (self.pos >= self.input.len) return Token{ .tag = TokenTag.Eof, .data = TokenData{ .Int = 0 } };

    const c = self.input[self.pos];
    if (c == '(') {
        self.pos += 1;
        return Token{ .tag = TokenTag.LParen, .data = TokenData{ .Int = 0 } };
    }
    if (c == ')') {
        self.pos += 1;
        return Token{ .tag = TokenTag.RParen, .data = TokenData{ .Int = 0 } };
    }

    if (is_digit(c) or (c == '-' and self.pos + 1 < self.input.len and is_digit(self.input[self.pos + 1]))) {
        const start = self.pos;
        if (self.input[self.pos] == '-') self.pos += 1;
        while (self.pos < self.input.len and is_digit(self.input[self.pos])) {
            self.pos += 1;
        }
        const slice = self.input[start..self.pos];
        const val = try util.parse_int(slice);
        return Token{ .tag = TokenTag.Int, .data = TokenData{ .Int = val } };
    }

    // Symbol
    const start = self.pos;
    while (self.pos < self.input.len and !is_whitespace(self.input[self.pos]) and self.input[self.pos] != '(' and self.input[self.pos] != ')') {
        self.pos += 1;
    }
    const sym = self.input[start..self.pos];
    return Token{ .tag = TokenTag.Symbol, .data = TokenData{ .Symbol = sym } };
}

pub fn peek_token(self: *Tokenizer) !Token {
    const saved_pos = self.pos;
    const tok = try self.next_token();
    self.pos = saved_pos;
    return tok;
}
