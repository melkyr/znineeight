pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    file_id: u32,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    string_buf: *U8ArrayList,

    pub fn init(source: []const u8, file_id: u32, interner: *StringInterner, diag: *DiagnosticCollector, alloc: *Sand) Lexer {
        var sb_raw = alloc_mod.sandAlloc(alloc, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
        var sb_ptr = @ptrCast(*U8ArrayList, sb_raw);
        sb_ptr.* = ga_mod.byteArrayListInit(alloc);
        return Lexer{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
            .file_id = file_id,
            .interner = interner,
            .diag = diag,
            .string_buf = sb_ptr,
        };
    }

    pub fn nextToken(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        if (self.isAtEnd()) return self.makeToken(.eof, self.pos, .{ .none = {} });

        var start = self.pos;
        var c = self.advance();
        switch (c) {
            '(' => return self.makeToken(.lparen, start, .{ .none = {} }),
            ')' => return self.makeToken(.rparen, start, .{ .none = {} }),
            '[' => return self.makeToken(.lbracket, start, .{ .none = {} }),
            ']' => return self.makeToken(.rbracket, start, .{ .none = {} }),
            '{' => return self.makeToken(.lbrace, start, .{ .none = {} }),
            '}' => return self.makeToken(.rbrace, start, .{ .none = {} }),
            ';' => return self.makeToken(.semicolon, start, .{ .none = {} }),
            ':' => return self.makeToken(.colon, start, .{ .none = {} }),
            ',' => return self.makeToken(.comma, start, .{ .none = {} }),
            '.' => {
                if (self.match('.')) {
                    if (self.match('.')) return self.makeToken(.dot_dot_dot, start, .{ .none = {} });
                    return self.makeToken(.dot_dot, start, .{ .none = {} });
                }
                if (self.match('{')) return self.makeToken(.dot_lbrace, start, .{ .none = {} });
                if (self.match('*')) return self.makeToken(.dot_star, start, .{ .none = {} });
                return self.makeToken(.dot, start, .{ .none = {} });
            },
            '+' => {
                if (self.match('=')) return self.makeToken(.plus_eq, start, .{ .none = {} });
                return self.makeToken(.plus, start, .{ .none = {} });
            },
            '-' => {
                if (self.match('=')) return self.makeToken(.minus_eq, start, .{ .none = {} });
                return self.makeToken(.minus, start, .{ .none = {} });
            },
            '*' => {
                if (self.match('=')) return self.makeToken(.star_eq, start, .{ .none = {} });
                return self.makeToken(.star, start, .{ .none = {} });
            },
            '/' => {
                if (self.match('=')) return self.makeToken(.slash_eq, start, .{ .none = {} });
                return self.makeToken(.slash, start, .{ .none = {} });
            },
            '%' => {
                if (self.match('=')) return self.makeToken(.percent_eq, start, .{ .none = {} });
                return self.makeToken(.percent, start, .{ .none = {} });
            },
            '&' => {
                if (self.match('=')) return self.makeToken(.ampersand_eq, start, .{ .none = {} });
                return self.makeToken(.ampersand, start, .{ .none = {} });
            },
            '|' => {
                if (self.match('=')) return self.makeToken(.pipe_eq, start, .{ .none = {} });
                return self.makeToken(.pipe, start, .{ .none = {} });
            },
            '=' => {
                if (self.match('=')) return self.makeToken(.eq_eq, start, .{ .none = {} });
                if (self.match('>')) return self.makeToken(.fat_arrow, start, .{ .none = {} });
                return self.makeToken(.eq, start, .{ .none = {} });
            },
            '!' => {
                if (self.match('=')) return self.makeToken(.bang_eq, start, .{ .none = {} });
                return self.makeToken(.bang, start, .{ .none = {} });
            },
            '<' => {
                if (self.match('<')) {
                    if (self.match('=')) return self.makeToken(.shl_eq, start, .{ .none = {} });
                    return self.makeToken(.shl, start, .{ .none = {} });
                }
                if (self.match('=')) return self.makeToken(.less_eq, start, .{ .none = {} });
                return self.makeToken(.less, start, .{ .none = {} });
            },
            '>' => {
                if (self.match('>')) {
                    if (self.match('=')) return self.makeToken(.shr_eq, start, .{ .none = {} });
                    return self.makeToken(.shr, start, .{ .none = {} });
                }
                if (self.match('=')) return self.makeToken(.greater_eq, start, .{ .none = {} });
                return self.makeToken(.greater, start, .{ .none = {} });
            },
            '^' => {
                if (self.match('=')) return self.makeToken(.caret_eq, start, .{ .none = {} });
                return self.makeToken(.caret, start, .{ .none = {} });
            },
            '~' => return self.makeToken(.tilde, start, .{ .none = {} }),
            '?' => return self.makeToken(.question_mark, start, .{ .none = {} }),
            '@' => {
                if (isAlpha(self.peek())) {
                    return self.scanBuiltinIdentifier(start);
                }
                diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                    .level = @intCast(u8, 0),
                    .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1004_BARE_AT_SIGN)),
                    .file_id = self.file_id,
                    .span_start = @intCast(u32, start),
                    .span_end = @intCast(u32, self.pos),
                    .message = "bare '@' is not valid; expected builtin name (e.g., @sizeOf)",
                });
                return self.makeErrorToken(start);
            },
            '"' => return self.scanString(start),
            '\'' => return self.scanChar(start),
            else => {
                if (isAlpha(c) or c == '_') return self.scanIdentifierOrKeyword(start);
                if (isDigit(c)) return self.scanNumber(start, c);
                diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                    .level = @intCast(u8, 0),
                    .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1005_UNRECOGNIZED_CHAR)),
                    .file_id = self.file_id,
                    .span_start = @intCast(u32, start),
                    .span_end = @intCast(u32, self.pos),
                    .message = "unrecognized character",
                });
                return self.makeErrorToken(start);
            },
        }
    }

    fn advance(self: *Lexer) u8 {
        if (self.pos >= self.source.len) return 0;
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
        if (self.pos >= self.source.len) return 0;
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
        if (self.peek() != expected) return false;
        _ = self.advance();
        return true;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (!self.isAtEnd()) {
            var c = self.peek();
            switch (c) {
                ' ', '\t', '\n', '\r' => {
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekN(1) == '/') {
                        _ = self.advance();
                        _ = self.advance();
                        while (!self.isAtEnd() and self.peek() != '\n') {
                            _ = self.advance();
                        }
                    } else if (self.peekN(1) == '*') {
                        _ = self.advance();
                        _ = self.advance();
                        var depth: u32 = 1;
                        while (!self.isAtEnd() and depth > 0) {
                            if (self.peek() == '*' and self.peekN(1) == '/') {
                                _ = self.advance();
                                _ = self.advance();
                                depth -= 1;
                            } else if (self.peek() == '/' and self.peekN(1) == '*') {
                                _ = self.advance();
                                _ = self.advance();
                                depth += 1;
                            } else {
                                _ = self.advance();
                            }
                        }
                        if (depth > 0) {
                            diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                                .level = @intCast(u8, 0),
                                .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1001_UNTERMINATED_BLOCK_COMMENT)),
                                .file_id = self.file_id,
                                .span_start = @intCast(u32, self.pos),
                                .span_end = @intCast(u32, self.pos),
                                .message = "unterminated block comment",
                            });
                        }
                    } else {
                        return;
                    }
                },
                else => return,
            }
        }
    }

    fn makeToken(self: *Lexer, kind: TokenKind, start: usize, value: TokenValue) Token {
        var span_len = self.pos - start;
        return Token{
            .kind = kind,
            .span_start = @intCast(u32, start),
            .span_len = @intCast(u16, span_len),
            .value = value,
        };
    }

    fn makeErrorToken(self: *Lexer, start: usize) Token {
        return Token{
            .kind = .err_token,
            .span_start = @intCast(u32, start),
            .span_len = 1,
            .value = TokenValue{ .none = {} },
        };
    }

    fn scanString(self: *Lexer, start: usize) Token {
        self.string_buf.len = 0;
        while (!self.isAtEnd()) {
            var c = self.peek();
            if (c == '"') {
                _ = self.advance();
                var text: []const u8 = undefined;
                var sb_slice = ga_mod.byteArrayListGetSlice(self.string_buf);
                if (sb_slice.len > 0) {
                    text = sb_slice;
                } else {
                    text = "";
                }
                var id = self.interner.intern(text);
                return Token{
                    .kind = .string_literal,
                    .span_start = @intCast(u32, start),
                    .span_len = @intCast(u16, self.pos - start),
                    .value = TokenValue{ .string_id = id },
                };
            }
            if (c == '\n' or c == 0) {
                diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                    .level = @intCast(u8, 0),
                    .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1000_UNTERMINATED_STRING)),
                    .file_id = self.file_id,
                    .span_start = @intCast(u32, start),
                    .span_end = @intCast(u32, self.pos),
                    .message = "unterminated string literal",
                });
                return self.makeErrorToken(start);
            }
            _ = self.advance();
            if (c == '\\') {
                ga_mod.byteArrayListAppend(self.string_buf, self.parseEscapeSequence());
            } else {
                ga_mod.byteArrayListAppend(self.string_buf, c);
            }
        }
        return self.makeErrorToken(start);
    }

    fn scanChar(self: *Lexer, start: usize) Token {
        if (self.isAtEnd() or self.peek() == '\'') {
            diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                .level = @intCast(u8, 0),
                .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1002_INVALID_CHAR_LITERAL)),
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "empty character literal",
            });
            if (self.peek() == '\'') { _ = self.advance(); }
            return self.makeToken(.char_literal, start, .{ .int_val = @intCast(u64, 0) });
        }
        var value: u32 = 0;
        var c = self.advance();
        if (c == '\\') {
            value = @intCast(u32, self.parseEscapeSequence());
        } else {
            value = @intCast(u32, c);
        }
        if (self.peek() != '\'') {
            diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                .level = @intCast(u8, 0),
                .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1002_INVALID_CHAR_LITERAL)),
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "expected closing ' in character literal",
            });
        } else {
            _ = self.advance();
        }
        return Token{
            .kind = .char_literal,
            .span_start = @intCast(u32, start),
            .span_len = @intCast(u16, self.pos - start),
            .value = TokenValue{ .int_val = @intCast(u64, value) },
        };
    }

    fn scanNumber(self: *Lexer, start: usize, first: u8) Token {
        var is_float = false;
        var base: u8 = 10;

        if (first == '0' and !self.isAtEnd()) {
            var next = self.peek();
            if (next == 'x' or next == 'X') {
                base = 16; _ = self.advance();
            } else if (next == 'b' or next == 'B') {
                base = 2; _ = self.advance();
            } else if (next == 'o' or next == 'O') {
                base = 8; _ = self.advance();
            }
        }

        while (!self.isAtEnd()) {
            var c = self.peek();
            if (c == '_') { _ = self.advance(); continue; }
            if (!isDigitInBase(c, base)) break;
            _ = self.advance();
        }

        if (base == 10 and self.peek() == '.' and self.peekN(1) != '.') {
            _ = self.advance();
            is_float = true;
            while (!self.isAtEnd()) {
                var c = self.peek();
                if (c == '_') { _ = self.advance(); continue; }
                if (!isDigit(c)) break;
                _ = self.advance();
            }
        }

        if (base == 10 and (self.peek() == 'e' or self.peek() == 'E')) {
            _ = self.advance();
            if (self.peek() == '+' or self.peek() == '-') { _ = self.advance(); }
            while (!self.isAtEnd() and isDigit(self.peek())) {
                _ = self.advance();
            }
            is_float = true;
        }

        var text = self.source[start..self.pos];

        if (is_float) {
            var value = parseF64(text);
            return self.makeToken(.float_literal, start, .{ .float_val = value });
        } else {
            var value = parseU64(text, base);
            if (value == 0xFFFFFFFFFFFFFFFF and !isU64MaxLiteral(text)) {
                diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                    .level = @intCast(u8, 1),
                    .code = @intCast(u16, @enumToInt(ErrorCode.WARN_1011_INTEGER_OVERFLOW)),
                    .file_id = self.file_id,
                    .span_start = @intCast(u32, start),
                    .span_end = @intCast(u32, self.pos),
                    .message = "integer literal overflow; value truncated",
                });
            }
            return self.makeToken(.integer_literal, start, .{ .int_val = value });
        }
    }

    fn scanIdentifierOrKeyword(self: *Lexer, start: usize) Token {
        while (!self.isAtEnd()) {
            var c = self.peek();
            if (!isAlpha(c) and !isDigit(c) and c != '_') break;
            _ = self.advance();
        }

        var text = self.source[start..self.pos];

        if (text.len == 1 and text[0] == '_') {
            return self.makeToken(.underscore, start, .{ .none = {} });
        }

        if (token_mod.lookupKeyword(text)) |kind| {
            return self.makeToken(kind, start, .{ .none = {} });
        }

        var string_id = self.interner.intern(text);
        return self.makeToken(.identifier, start, .{ .string_id = string_id });
    }

    fn scanBuiltinIdentifier(self: *Lexer, start: usize) Token {
        while (!self.isAtEnd()) {
            var c = self.peek();
            if (!isAlphaNum(c) and c != '_') break;
            _ = self.advance();
        }
        var text = self.source[start..self.pos];
        var string_id = self.interner.intern(text);
        return self.makeToken(.builtin_identifier, start, .{ .string_id = string_id });
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

fn hexDigitValue(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 0xFF;
}

fn parseHexEscape(self: *Lexer) u8 {
    var value: u8 = 0;
    var count: u8 = 0;
    while (count < 2 and !self.isAtEnd()) {
        var digit = hexDigitValue(self.peek());
        if (digit == 0xFF) break;
        value = value * 16 + digit;
        _ = self.advance();
        count += 1;
    }
    if (count == 0) {
        diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
            .level = @intCast(u8, 0),
            .code = @intCast(u16, @enumToInt(ErrorCode.ERR_1003_INVALID_ESCAPE)),
            .file_id = self.file_id,
            .span_start = @intCast(u32, self.pos - 2),
            .span_end = @intCast(u32, self.pos),
            .message = "\\x requires at least one hex digit",
        });
    }
    return value;
}

fn parseEscapeSequence(self: *Lexer) u8 {
    if (self.isAtEnd()) return '\\';
    var c = self.advance();
    switch (c) {
        'n' => return '\n',
        't' => return '\t',
        'r' => return '\r',
        '\\' => return '\\',
        '"' => return '"',
        '\'' => return '\'',
        '0' => return 0,
        'x' => return self.parseHexEscape(),
        else => {
            diagnosticArrayListAppend(self.diag.diagnostics, Diagnostic{
                .level = @intCast(u8, 1),
                .code = @intCast(u16, @enumToInt(ErrorCode.WARN_1010_UNRECOGNIZED_ESCAPE)),
                .file_id = self.file_id,
                .span_start = @intCast(u32, self.pos - 2),
                .span_end = @intCast(u32, self.pos),
                .message = "unrecognized escape sequence",
            });
            return c;
        },
    }
}

fn isDigitInBase(c: u8, base: u8) bool {
    switch (base) {
        2 => return c >= '0' and c <= '1',
        8 => return c >= '0' and c <= '7',
        10 => return c >= '0' and c <= '9',
        16 => return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'),
        else => return false,
    }
}

fn parseU64(text: []const u8, base: u8) u64 {
    var result: u64 = 0;
    var i: usize = 0;

    if (text.len > 2 and text[0] == '0') {
        var p = text[1];
        if (p == 'x' or p == 'X' or p == 'b' or p == 'B' or p == 'o' or p == 'O') {
            i = 2;
        }
    }

    while (i < text.len) {
        var c = text[i];
        i += 1;
        if (c == '_') continue;

        var digit: u64 = switch (c) {
            '0'...'9' => @intCast(u64, c - '0'),
            'a'...'f' => @intCast(u64, c - 'a' + 10),
            'A'...'F' => @intCast(u64, c - 'A' + 10),
            else => break,
        };

        if (digit >= @intCast(u64, base)) break;

        var max_before_mul = 0xFFFFFFFFFFFFFFFF / @intCast(u64, base);
        if (result > max_before_mul) return 0xFFFFFFFFFFFFFFFF;
        result = result * @intCast(u64, base);
        if (result > 0xFFFFFFFFFFFFFFFF - digit) return 0xFFFFFFFFFFFFFFFF;
        result += digit;
    }

    return result;
}

fn parseF64(text: []const u8) f64 {
    var result: f64 = 0.0;
    var i: usize = 0;
    var negative = false;

    if (i < text.len and text[i] == '-') { negative = true; i += 1; }
    if (i < text.len and text[i] == '+') { i += 1; }

    while (i < text.len) {
        var c = text[i];
        i += 1;
        if (c == '_') continue;
        if (c == '.' or c == 'e' or c == 'E') { i -= 1; break; }
        if (!isDigit(c)) { i -= 1; break; }
        result = result * 10.0 + @intToFloat(f64, @intCast(i32, c - '0'));
    }

    if (i < text.len and text[i] == '.') {
        i += 1;
        var frac_mul: f64 = 0.1;
        while (i < text.len) {
            var c = text[i];
            i += 1;
            if (c == '_') continue;
            if (c == 'e' or c == 'E') break;
            if (!isDigit(c)) break;
            result += @intToFloat(f64, @intCast(i32, c - '0')) * frac_mul;
            frac_mul *= 0.1;
        }
    }

    if (i < text.len and (text[i] == 'e' or text[i] == 'E')) {
        i += 1;
        var exp_neg = false;
        if (i < text.len and text[i] == '-') { exp_neg = true; i += 1; }
        if (i < text.len and text[i] == '+') { i += 1; }

        var exp: i32 = 0;
        while (i < text.len and isDigit(text[i])) {
            exp = exp * 10 + @intCast(i32, text[i] - '0');
            i += 1;
        }

        var power: f64 = 1.0;
        var e: i32 = 0;
        while (e < exp) {
            power *= 10.0;
            e += 1;
        }
        if (exp_neg) {
            result /= power;
        } else {
            result *= power;
        }
    }

    if (negative) result = -result;
    return result;
}

fn isU64MaxLiteral(text: []const u8) bool {
    if (text.len < 2) return false;
    var val = parseU64(text, 16);
    return val == 0xFFFFFFFFFFFFFFFF;
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

const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const TokenValue = token_mod.TokenValue;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Diagnostic = @import("diagnostics.zig").Diagnostic;
const ErrorCode = @import("diagnostics.zig").ErrorCode;
const diagnosticArrayListAppend = @import("diagnostics.zig").diagnosticArrayListAppend;
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const ga_mod = @import("growable_array.zig");
const U8ArrayList = ga_mod.U8ArrayList;
