const util = @import("util.zig");

pub const Token = union(enum) {
    LParen: void,
    RParen: void,
    Int: i64,
    Symbol: []const u8,
    Eof: void,
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

pub fn next_token(self: *Tokenizer) util.LispError!Token {
    skip_whitespace(self);
    if (self.pos >= self.input.len) return Token.Eof;

    const c = self.input[self.pos];
    if (c == '(') {
        self.pos += 1;
        return Token.LParen;
    }
    if (c == ')') {
        self.pos += 1;
        return Token.RParen;
    }

    if (is_digit(c) or (c == '-' and self.pos + 1 < self.input.len and is_digit(self.input[self.pos + 1]))) {
        const start = self.pos;
        if (self.input[self.pos] == '-') self.pos += 1;
        while (self.pos < self.input.len and is_digit(self.input[self.pos])) {
            self.pos += 1;
        }
        const slice = self.input[start..self.pos];
        const val = try util.parse_int(slice);
        return Token{ .Int = val };
    }

    // Symbol
    const start = self.pos;
    while (self.pos < self.input.len and !is_whitespace(self.input[self.pos]) and self.input[self.pos] != '(' and self.input[self.pos] != ')') {
        self.pos += 1;
    }
    const sym = self.input[start..self.pos];
    return Token{ .Symbol = sym };
}

pub fn peek_token(self: *Tokenizer) util.LispError!Token {
    const saved_pos = self.pos;
    const tok = try next_token(self);
    self.pos = saved_pos;
    return tok;
}
