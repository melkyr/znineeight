pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    start: usize,
    interner: *StringInterner,
    diag: *DiagnosticCollector,

    pub fn init(source: []const u8, interner: *StringInterner, diag: *DiagnosticCollector) Lexer {
        return Lexer{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
            .start = 0,
            .interner = interner,
            .diag = diag,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        if (self.isAtEnd()) return self.makeToken(.eof);

        var c = self.advance();
        switch (c) {
            '(' => return self.makeToken(.lparen),
            ')' => return self.makeToken(.rparen),
            '{' => return self.makeToken(.lbrace),
            '}' => return self.makeToken(.rbrace),
            ';' => return self.makeToken(.semicolon),
            ':' => return self.makeToken(.colon),
            ',' => return self.makeToken(.comma),
            '.' => {
                if (self.match('.')) {
                    if (self.match('.')) return self.makeToken(.dot_dot_dot);
                    return self.makeToken(.dot_dot);
                }
                if (self.match('{')) return self.makeToken(.dot_lbrace);
                if (self.match('*')) return self.makeToken(.dot_star);
                return self.makeToken(.dot);
            },
            '+' => {
                if (self.match('=')) return self.makeToken(.plus_eq);
                return self.makeToken(.plus);
            },
            '-' => {
                if (self.match('=')) return self.makeToken(.minus_eq);
                return self.makeToken(.minus);
            },
            '*' => {
                if (self.match('=')) return self.makeToken(.star_eq);
                return self.makeToken(.star);
            },
            '/' => {
                if (self.match('=')) return self.makeToken(.slash_eq);
                return self.makeToken(.slash);
            },
            '%' => {
                if (self.match('=')) return self.makeToken(.percent_eq);
                return self.makeToken(.percent);
            },
            '&' => {
                if (self.match('=')) return self.makeToken(.ampersand_eq);
                return self.makeToken(.ampersand);
            },
            '|' => {
                if (self.match('=')) return self.makeToken(.pipe_eq);
                return self.makeToken(.pipe);
            },
            '=' => {
                if (self.match('=')) return self.makeToken(.eq_eq);
                if (self.match('>')) return self.makeToken(.fat_arrow);
                return self.makeToken(.eq);
            },
            '!' => {
                if (self.match('=')) return self.makeToken(.bang_eq);
                return self.makeToken(.bang);
            },
            '<' => {
                if (self.match('<')) {
                    if (self.match('=')) return self.makeToken(.shl_eq);
                    return self.makeToken(.shl);
                }
                if (self.match('=')) return self.makeToken(.less_eq);
                return self.makeToken(.less);
            },
            '>' => {
                if (self.match('>')) {
                    if (self.match('=')) return self.makeToken(.shr_eq);
                    return self.makeToken(.shr);
                }
                if (self.match('=')) return self.makeToken(.greater_eq);
                return self.makeToken(.greater);
            },
            '^' => {
                if (self.match('=')) return self.makeToken(.caret_eq);
                return self.makeToken(.caret);
            },
            '~' => return self.makeToken(.tilde),
            '?' => return self.makeToken(.question_mark),
            '@' => {
                if (isAlpha(self.peek())) {
                    return self.scanBuiltinIdentifier();
                }
                return self.makeToken(.at_sign);
            },
            '"' => return self.scanString(),
            '\'' => return self.scanChar(),
            else => {
                if (isAlpha(c) or c == '_') return self.scanIdentifierOrKeyword(c);
                if (isDigit(c)) return self.scanNumber(c);
                return self.makeErrorToken();
            },
        }
    }

    fn advance(self: *Lexer) u8 {
        var c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.col = 1;
        } else {
            self.col += 1;
        }
        return c;
    }

    fn peek(self: *Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    fn peekN(self: *Lexer, n: usize) u8 {
        var idx = self.pos + n;
        if (idx >= self.source.len) return 0;
        return self.source[idx];
    }

    fn isAtEnd(self: *Lexer) bool {
        return self.pos >= self.source.len;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != expected) return false;
        self.pos += 1;
        self.col += 1;
        return true;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (!self.isAtEnd()) {
            var c = self.peek();
            switch (c) {
                ' ', '\t', '\n', '\r' => {
                    self.advance();
                },
                '/' => {
                    if (self.peekN(1) == '/') {
                        while (!self.isAtEnd() and self.peek() != '\n') {
                            self.advance();
                        }
                    } else if (self.peekN(1) == '*') {
                        self.advance();
                        self.advance();
                        while (!self.isAtEnd()) {
                            if (self.peek() == '*' and self.peekN(1) == '/') {
                                self.advance();
                                self.advance();
                                break;
                            }
                            self.advance();
                        }
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }
    }

    fn makeToken(self: *Lexer, kind: TokenKind) Token {
        var span_len = self.pos - self.start;
        return Token{
            .kind = kind,
            .span_start = @intCast(u32, self.start),
            .span_len = @intCast(u16, span_len),
            .value = TokenValue{ .none = {} },
        };
    }

    fn makeErrorToken(self: *Lexer) Token {
        return Token{
            .kind = .err_token,
            .span_start = @intCast(u32, self.start),
            .span_len = @intCast(u16, self.pos - self.start),
            .value = TokenValue{ .none = {} },
        };
    }

    fn scanString(self: *Lexer) Token {
        var buf: [1024]u8 = undefined;
        var buf_len: u32 = 0;
        while (!self.isAtEnd()) {
            var c = self.advance();
            if (c == '"') {
                var text: []const u8 = undefined;
                if (buf_len > 0) {
                    text = buf[0..@intCast(usize, buf_len)];
                } else {
                    text = "";
                }
                var id = self.interner.intern(text) catch @panic("intern");
                return Token{
                    .kind = .string_literal,
                    .span_start = @intCast(u32, self.start),
                    .span_len = @intCast(u16, self.pos - self.start),
                    .value = TokenValue{ .string_id = id },
                };
            }
            if (c == '\\') {
                if (self.isAtEnd()) break;
                var esc = self.advance();
                switch (esc) {
                    'n' => { if (buf_len < 1024) { buf[@intCast(usize, buf_len)] = '\n'; buf_len += 1; } },
                    't' => { if (buf_len < 1024) { buf[@intCast(usize, buf_len)] = '\t'; buf_len += 1; } },
                    '\\' => { if (buf_len < 1024) { buf[@intCast(usize, buf_len)] = '\\'; buf_len += 1; } },
                    '"' => { if (buf_len < 1024) { buf[@intCast(usize, buf_len)] = '"'; buf_len += 1; } },
                    'x' => {
                        var hd = self.advance();
                        var h1 = hexDigit(hd);
                        var h2: u8 = 0;
                        if (isHexDigit(self.peek())) {
                            h2 = hexDigit(self.advance());
                        }
                        if (buf_len < 1024) {
                            buf[@intCast(usize, buf_len)] = (h1 << 4) | h2;
                            buf_len += 1;
                        }
                    },
                    'u' => {
                        if (self.advance() == '{') {
                            var cp: u32 = 0;
                            while (!self.isAtEnd()) {
                                var dc = self.peek();
                                if (dc == '}') {
                                    self.advance();
                                    break;
                                }
                                if (isHexDigit(dc)) {
                                    cp = cp * 16 + hexDigit(self.advance());
                                } else {
                                    self.advance();
                                }
                            }
                            if (cp < 0x80 and buf_len < 1024) {
                                buf[@intCast(usize, buf_len)] = @intCast(u8, cp);
                                buf_len += 1;
                            }
                        }
                    },
                    else => {},
                }
            } else {
                if (buf_len < 1024) {
                    buf[@intCast(usize, buf_len)] = c;
                    buf_len += 1;
                }
            }
        }
        return self.makeErrorToken();
    }

    fn scanChar(self: *Lexer) Token {
        if (self.isAtEnd()) return self.makeErrorToken();
        var val: u64 = 0;
        var c = self.advance();
        if (c == '\\') {
            var esc = self.advance();
            switch (esc) {
                'n' => val = '\n',
                't' => val = '\t',
                '\\' => val = '\\',
                '\'' => val = '\'',
                'x' => {
                    var h1 = hexDigit(self.advance());
                    var h2: u8 = 0;
                    if (isHexDigit(self.peek())) {
                        h2 = hexDigit(self.advance());
                    }
                    val = (h1 << 4) | h2;
                },
                else => {},
            }
        } else {
            val = c;
        }
        if (!self.isAtEnd() and self.peek() == '\'') {
            self.advance();
            if (val <= 0xFF) {
                return Token{
                    .kind = .char_literal,
                    .span_start = @intCast(u32, self.start),
                    .span_len = @intCast(u16, self.pos - self.start),
                    .value = TokenValue{ .int_val = val },
                };
            }
        }
        return self.makeErrorToken();
    }

    fn scanNumber(self: *Lexer, first: u8) Token {
        self.start = self.pos - 1;
        if (first == '0') {
            var next = self.peek();
            if (next == 'x' or next == 'X') {
                self.advance();
                return self.scanInteger(16);
            }
            if (next == 'b' or next == 'B') {
                self.advance();
                return self.scanInteger(2);
            }
            if (next == 'o' or next == 'O') {
                self.advance();
                return self.scanInteger(8);
            }
        }
        return self.scanInteger(10);
    }

    fn scanInteger(self: *Lexer, base: u8) Token {
        var val: u64 = 0;
        var overflow: bool = false;
        while (isDigit(self.peek()) or (base == 16 and isHexDigit(self.peek())) or self.peek() == '_') {
            var c = self.advance();
            if (c == '_') continue;
            var digit = hexDigit(c);
            var prev = val;
            val = val *% base + digit;
            if (val < prev and !overflow) {
                overflow = true;
            }
        }
        _ = overflow;
        return Token{
            .kind = .integer_literal,
            .span_start = @intCast(u32, self.start),
            .span_len = @intCast(u16, self.pos - self.start),
            .value = TokenValue{ .int_val = val },
        };
    }

    fn scanIdentifierOrKeyword(self: *Lexer, first: u8) Token {
        _ = first;
        var buf: [128]u8 = undefined;
        var buf_len: u32 = 0;
        buf[@intCast(usize, buf_len)] = first;
        buf_len += 1;
        while (isAlphaNum(self.peek())) {
            var c = self.advance();
            if (buf_len < 128) {
                buf[@intCast(usize, buf_len)] = c;
                buf_len += 1;
            }
        }
        var text = buf[0..@intCast(usize, buf_len)];
        var kw = lookupKeyword(text);
        if (kw) |kind| {
            return self.makeToken(kind);
        }
        var id = self.interner.intern(text) catch @panic("intern");
        return Token{
            .kind = .identifier,
            .span_start = @intCast(u32, self.start),
            .span_len = @intCast(u16, self.pos - self.start),
            .value = TokenValue{ .string_id = id },
        };
    }

    fn scanBuiltinIdentifier(self: *Lexer) Token {
        _ = self;
        return Token{
            .kind = .builtin_identifier,
            .span_start = @intCast(u32, self.start),
            .span_len = @intCast(u16, self.pos - self.start),
            .value = TokenValue{ .none = {} },
        };
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaNum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

fn isHexDigit(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn hexDigit(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 0;
}

fn lookupKeyword(ident: []const u8) ?TokenKind {
    if (ident.len == 0) return null;
    switch (ident[0]) {
        'a' => {
            if (memEql(ident, "and")) return .kw_and;
        },
        'b' => {
            if (memEql(ident, "break")) return .kw_break;
            if (memEql(ident, "bool")) return .kw_bool;
        },
        'c' => {
            if (memEql(ident, "catch")) return .kw_catch;
            if (memEql(ident, "continue")) return .kw_continue;
            if (memEql(ident, "const")) return .kw_const;
            if (memEql(ident, "c_char")) return .kw_c_char;
        },
        'd' => {
            if (memEql(ident, "defer")) return .kw_defer;
        },
        'e' => {
            if (memEql(ident, "else")) return .kw_else;
            if (memEql(ident, "enum")) return .kw_enum;
            if (memEql(ident, "error")) return .kw_error;
            if (memEql(ident, "export")) return .kw_export;
            if (memEql(ident, "extern")) return .kw_extern;
            if (memEql(ident, "errdefer")) return .kw_errdefer;
        },
        'f' => {
            if (memEql(ident, "fn")) return .kw_fn;
            if (memEql(ident, "for")) return .kw_for;
            if (memEql(ident, "false")) return .kw_false;
        },
        'i' => {
            if (memEql(ident, "if")) return .kw_if;
        },
        'n' => {
            if (memEql(ident, "null")) return .kw_null;
            if (memEql(ident, "noreturn")) return .kw_noreturn;
        },
        'o' => {
            if (memEql(ident, "or")) return .kw_or;
            if (memEql(ident, "orelse")) return .kw_orelse;
        },
        'p' => {
            if (memEql(ident, "pub")) return .kw_pub;
        },
        'r' => {
            if (memEql(ident, "return")) return .kw_return;
        },
        's' => {
            if (memEql(ident, "struct")) return .kw_struct;
            if (memEql(ident, "switch")) return .kw_switch;
        },
        't' => {
            if (memEql(ident, "true")) return .kw_true;
            if (memEql(ident, "try")) return .kw_try;
            if (memEql(ident, "test")) return .kw_test;
        },
        'u' => {
            if (memEql(ident, "union")) return .kw_union;
            if (memEql(ident, "undefined")) return .kw_undefined;
            if (memEql(ident, "unreachable")) return .kw_unreachable;
        },
        'v' => {
            if (memEql(ident, "var")) return .kw_var;
            if (memEql(ident, "void")) return .kw_void;
        },
        'w' => {
            if (memEql(ident, "while")) return .kw_while;
        },
        else => {},
    }
    return null;
}

fn memEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const TokenValue = @import("token.zig").TokenValue;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
