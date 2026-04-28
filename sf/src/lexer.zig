pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    file_id: u32,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    string_buf: *U8ArrayList,
};

pub fn lexerInit(source: []const u8, file_id: u32, interner: *StringInterner, diag: *DiagnosticCollector, alloc: *Sand) Lexer {
    var sb_raw = alloc_mod.sandAlloc(alloc, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var sb_ptr = @ptrCast(*U8ArrayList, sb_raw);
    sb_ptr.* = ga_mod.byteArrayListInit(alloc);
    return Lexer{
        .source = source,
        .pos = @intCast(usize, 0),
        .line = @intCast(u32, 1),
        .col = @intCast(u32, 1),
        .file_id = file_id,
        .interner = interner,
        .diag = diag,
        .string_buf = sb_ptr,
    };
}

pub fn lexerNextToken(self: *Lexer) Token {
    lexerSkipWSC(self);
    if (lexerIsAtEnd(self)) return lexerMakeToken(self, TokenKind.eof, self.pos, .{ .none = {} });

    var start = self.pos;
    var c = lexerAdvance(self);
    switch (c) {
        '(' => return lexerMakeToken(self, TokenKind.lparen, start, .{ .none = {} }),
        ')' => return lexerMakeToken(self, TokenKind.rparen, start, .{ .none = {} }),
        '[' => return lexerMakeToken(self, TokenKind.lbracket, start, .{ .none = {} }),
        ']' => return lexerMakeToken(self, TokenKind.rbracket, start, .{ .none = {} }),
        '{' => return lexerMakeToken(self, TokenKind.lbrace, start, .{ .none = {} }),
        '}' => return lexerMakeToken(self, TokenKind.rbrace, start, .{ .none = {} }),
        ';' => return lexerMakeToken(self, TokenKind.semicolon, start, .{ .none = {} }),
        ':' => return lexerMakeToken(self, TokenKind.colon, start, .{ .none = {} }),
        ',' => return lexerMakeToken(self, TokenKind.comma, start, .{ .none = {} }),
        '.' => {
            if (lexerMatch(self, '.')) {
                if (lexerMatch(self, '.')) return lexerMakeToken(self, TokenKind.dot_dot_dot, start, .{ .none = {} });
                return lexerMakeToken(self, TokenKind.dot_dot, start, .{ .none = {} });
            }
            if (lexerMatch(self, '{')) return lexerMakeToken(self, TokenKind.dot_lbrace, start, .{ .none = {} });
            if (lexerMatch(self, '*')) return lexerMakeToken(self, TokenKind.dot_star, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.dot, start, .{ .none = {} });
        },
        '+' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.plus_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.plus, start, .{ .none = {} });
        },
        '-' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.minus_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.minus, start, .{ .none = {} });
        },
        '*' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.star_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.star, start, .{ .none = {} });
        },
        '/' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.slash_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.slash, start, .{ .none = {} });
        },
        '%' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.percent_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.percent, start, .{ .none = {} });
        },
        '&' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.ampersand_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.ampersand, start, .{ .none = {} });
        },
        '|' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.pipe_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.pipe, start, .{ .none = {} });
        },
        '=' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.eq_eq, start, .{ .none = {} });
            if (lexerMatch(self, '>')) return lexerMakeToken(self, TokenKind.fat_arrow, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.eq, start, .{ .none = {} });
        },
        '!' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.bang_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.bang, start, .{ .none = {} });
        },
        '<' => {
            if (lexerMatch(self, '<')) {
                if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.shl_eq, start, .{ .none = {} });
                return lexerMakeToken(self, TokenKind.shl, start, .{ .none = {} });
            }
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.less_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.less, start, .{ .none = {} });
        },
        '>' => {
            if (lexerMatch(self, '>')) {
                if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.shr_eq, start, .{ .none = {} });
                return lexerMakeToken(self, TokenKind.shr, start, .{ .none = {} });
            }
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.greater_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.greater, start, .{ .none = {} });
        },
        '^' => {
            if (lexerMatch(self, '=')) return lexerMakeToken(self, TokenKind.caret_eq, start, .{ .none = {} });
            return lexerMakeToken(self, TokenKind.caret, start, .{ .none = {} });
        },
        '~' => return lexerMakeToken(self, TokenKind.tilde, start, .{ .none = {} }),
        '?' => return lexerMakeToken(self, TokenKind.question_mark, start, .{ .none = {} }),
        '@' => {
            if (isAlpha(lexerPeek(self))) {
                return lexerScanBuiltinIdentifier(self, start);
            }
            const bare_at_msg: []const u8 = "bare '@' is not valid; expected builtin name (e.g., @sizeOf)";
            diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1004_BARE_AT_SIGN)), self.file_id, @intCast(u32, start), @intCast(u32, self.pos), bare_at_msg);
            return lexerMakeErrorToken(self, start);
        },
        '"' => return lexerScanString(self, start),
        '\'' => return lexerScanChar(self, start),
        else => {
            if (isAlpha(c) or c == '_') return lexerScanIdentifierOrKeyword(self, start);
            if (isDigit(c)) return lexerScanNumber(self, start, c);
            const unrecognized_msg: []const u8 = "unrecognized character";
            diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1005_UNRECOGNIZED_CHAR)), self.file_id, @intCast(u32, start), @intCast(u32, self.pos), unrecognized_msg);
            return lexerMakeErrorToken(self, start);
        },
    }
}

fn lexerAdvance(self: *Lexer) u8 {
    if (self.pos >= self.source.len) return @intCast(u8, 0);
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

fn lexerPeek(self: *Lexer) u8 {
    if (self.pos >= self.source.len) return @intCast(u8, 0);
    return self.source[self.pos];
}

fn lexerPeekN(self: *Lexer, n: usize) u8 {
    var idx = self.pos + n;
    if (idx >= self.source.len) return @intCast(u8, 0);
    return self.source[idx];
}

fn lexerIsAtEnd(self: *Lexer) bool {
    return self.pos >= self.source.len;
}

fn lexerMatch(self: *Lexer, expected: u8) bool {
    if (lexerPeek(self) != expected) return false;
    _ = lexerAdvance(self);
    return true;
}

fn lexerSkipWSC(self: *Lexer) void {
    while (!lexerIsAtEnd(self)) {
        var c = lexerPeek(self);
        switch (c) {
            ' ', '\t', '\n', '\r' => {
                _ = lexerAdvance(self);
            },
            '/' => {
                if (lexerPeekN(self, 1) == '/') {
                    _ = lexerAdvance(self);
                    _ = lexerAdvance(self);
                    while (!lexerIsAtEnd(self) and lexerPeek(self) != '\n') {
                        _ = lexerAdvance(self);
                    }
                } else if (lexerPeekN(self, 1) == '*') {
                    _ = lexerAdvance(self);
                    _ = lexerAdvance(self);
                    var depth: u32 = 1;
                    while (!lexerIsAtEnd(self) and depth > 0) {
                        if (lexerPeek(self) == '*' and lexerPeekN(self, 1) == '/') {
                            _ = lexerAdvance(self);
                            _ = lexerAdvance(self);
                            depth -= 1;
                        } else if (lexerPeek(self) == '/' and lexerPeekN(self, 1) == '*') {
                            _ = lexerAdvance(self);
                            _ = lexerAdvance(self);
                            depth += 1;
                        } else {
                            _ = lexerAdvance(self);
                        }
                    }
                    if (depth > 0) {
                        const unterminated_block_msg: []const u8 = "unterminated block comment";
                        diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1001_UNTERMINATED_BLOCK_COMMENT)), self.file_id, @intCast(u32, self.pos), @intCast(u32, self.pos), unterminated_block_msg);
                    }
                } else {
                    return;
                }
            },
            else => return,
        }
    }
}

fn lexerMakeToken(self: *Lexer, kind: TokenKind, start: usize, value: TokenValue) Token {
    var span_len = @intCast(u16, self.pos - start);
    return Token{
        .kind = kind,
        .span_start = @intCast(u32, start),
        .span_len = @intCast(u16, span_len),
        .value = value,
    };
}

fn lexerMakeErrorToken(self: *Lexer, start: usize) Token {
    return Token{
    
            .kind = TokenKind.err_token,
    .span_start = @intCast(u32, start),
    .span_len = @intCast(u16, 1),
    .value = TokenValue{ .none = {} },
    };
}

fn lexerScanString(self: *Lexer, start: usize) Token {
    self.string_buf.len = 0;
    while (!lexerIsAtEnd(self)) {
        var c = lexerPeek(self);
        if (c == '"') {
            _ = lexerAdvance(self);
            var text: []const u8 = undefined;
            var sb_slice = ga_mod.byteArrayListGetSlice(self.string_buf);
            if (sb_slice.len > 0) {
                text = sb_slice;
            } else {
                text = "";
            }
            var id = interner_mod.stringInternerIntern(self.interner, text);
            return Token{
                
            .kind = TokenKind.string_literal,
                .span_start = @intCast(u32, start),
                .span_len = @intCast(u16, self.pos - start),
                .value = TokenValue{ .string_id = id },
            };
        }
        if (c == '\n' or c == 0) {
            const unterminated_string_msg: []const u8 = "unterminated string literal";
            diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1000_UNTERMINATED_STRING)), self.file_id, @intCast(u32, start), @intCast(u32, self.pos), unterminated_string_msg);
            return lexerMakeErrorToken(self, start);
        }
        _ = lexerAdvance(self);
        if (c == '\\') {
            ga_mod.byteArrayListAppend(self.string_buf, lexerParseEscapeSequence(self));
        } else {
            ga_mod.byteArrayListAppend(self.string_buf, c);
        }
    }
    return lexerMakeErrorToken(self, start);
}

fn lexerScanChar(self: *Lexer, start: usize) Token {
    if (lexerIsAtEnd(self) or lexerPeek(self) == '\'') {
        const empty_char_msg: []const u8 = "empty character literal";
        diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1002_INVALID_CHAR_LITERAL)), self.file_id, @intCast(u32, start), @intCast(u32, self.pos), empty_char_msg);
        if (lexerPeek(self) == '\'') { _ = lexerAdvance(self); }
        return lexerMakeToken(self, TokenKind.char_literal, start, .{ .int_val = @intCast(u64, 0) });
    }
    var value: u32 = 0;
    var c = lexerAdvance(self);
    if (c == '\\') {
        value = @intCast(u32, lexerParseEscapeSequence(self));
    } else {
        value = @intCast(u32, c);
    }
    if (lexerPeek(self) != '\'') {
        const expected_close_msg: []const u8 = "expected closing ' in character literal";
        diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1002_INVALID_CHAR_LITERAL)), self.file_id, @intCast(u32, start), @intCast(u32, self.pos), expected_close_msg);
    } else {
        _ = lexerAdvance(self);
    }
    return Token{
        
            .kind = TokenKind.char_literal,
        .span_start = @intCast(u32, start),
        .span_len = @intCast(u16, self.pos - start),
        .value = TokenValue{ .int_val = @intCast(u64, value) },
    };
}

fn lexerScanNumber(self: *Lexer, start: usize, first: u8) Token {
    var is_float = false;
    var base: u8 = 10;

    if (first == '0' and !lexerIsAtEnd(self)) {
        var next = lexerPeek(self);
        if (next == 'x' or next == 'X') {
            base = 16; _ = lexerAdvance(self);
        } else if (next == 'b' or next == 'B') {
            base = 2; _ = lexerAdvance(self);
        } else if (next == 'o' or next == 'O') {
            base = 8; _ = lexerAdvance(self);
        }
    }

    while (!lexerIsAtEnd(self)) {
        var c = lexerPeek(self);
        if (c == '_') { _ = lexerAdvance(self); continue; }
        if (!isDigitInBase(c, base)) break;
        _ = lexerAdvance(self);
    }

    if (base == 10 and lexerPeek(self) == '.' and lexerPeekN(self, 1) != '.') {
        _ = lexerAdvance(self);
        is_float = true;
        while (!lexerIsAtEnd(self)) {
            var c = lexerPeek(self);
            if (c == '_') { _ = lexerAdvance(self); continue; }
            if (!isDigit(c)) break;
            _ = lexerAdvance(self);
        }
    }

    if (base == 10 and (lexerPeek(self) == 'e' or lexerPeek(self) == 'E')) {
        _ = lexerAdvance(self);
        if (lexerPeek(self) == '+' or lexerPeek(self) == '-') { _ = lexerAdvance(self); }
        while (!lexerIsAtEnd(self) and isDigit(lexerPeek(self))) {
            _ = lexerAdvance(self);
        }
        is_float = true;
    }

    var text = self.source[start..self.pos];

    if (is_float) {
        var value = parseF64(text);
        return lexerMakeToken(self, TokenKind.float_literal, start, .{ .float_val = value });
    } else {
        var value = parseU64(text, base);
        if (value == 0xFFFFFFFFFFFFFFFF and !isU64MaxLiteral(text)) {
            const overflow_msg: []const u8 = "integer literal overflow; value truncated";
            diag_mod.diagnosticCollectorAdd(self.diag, 1, @intCast(u16, @enumToInt(ErrorCode.WARN_1011_INTEGER_OVERFLOW)), self.file_id, @intCast(u32, start), @intCast(u32, self.pos), overflow_msg);
        }
        return lexerMakeToken(self, TokenKind.integer_literal, start, .{ .int_val = value });
    }
}

fn lexerScanIdentifierOrKeyword(self: *Lexer, start: usize) Token {
    while (!lexerIsAtEnd(self)) {
        var c = lexerPeek(self);
        if (!isAlpha(c) and !isDigit(c) and c != '_') break;
        _ = lexerAdvance(self);
    }

    var text = self.source[start..self.pos];

    if (text.len == 1 and text[0] == '_') {
        return lexerMakeToken(self, TokenKind.underscore, start, .{ .none = {} });
    }

    if (token_mod.lookupKeyword(text)) |kind| {
        return lexerMakeToken(self, kind, start, .{ .none = {} });
    }

    var string_id = interner_mod.stringInternerIntern(self.interner, text);
    return lexerMakeToken(self, TokenKind.identifier, start, .{ .string_id = string_id });
}

fn lexerScanBuiltinIdentifier(self: *Lexer, start: usize) Token {
    while (!lexerIsAtEnd(self)) {
        var c = lexerPeek(self);
        if (!isAlphaNum(c) and c != '_') break;
        _ = lexerAdvance(self);
    }
    var text = self.source[start..self.pos];
    var string_id = interner_mod.stringInternerIntern(self.interner, text);
    return lexerMakeToken(self, TokenKind.builtin_identifier, start, .{ .string_id = string_id });
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaNum(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

fn hexDigitValue(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return @intCast(u8, 255);
}

fn lexerParseHexEscape(self: *Lexer) u8 {
    var value: u8 = 0;
    var count: u8 = 0;
    while (count < 2 and !lexerIsAtEnd(self)) {
        var digit = hexDigitValue(lexerPeek(self));
        if (digit == 0xFF) break;
        value = value * 16 + digit;
        _ = lexerAdvance(self);
        count += 1;
    }
    if (count == 0) {
        const s_hex: []const u8 = "\\x requires at least one hex digit";
        diag_mod.diagnosticCollectorAdd(self.diag, 0, @intCast(u16, @enumToInt(ErrorCode.ERR_1003_INVALID_ESCAPE)), self.file_id, @intCast(u32, self.pos - 2), @intCast(u32, self.pos), s_hex);
    }
    return value;
}

fn lexerParseEscapeSequence(self: *Lexer) u8 {
    if (lexerIsAtEnd(self)) return '\\';
    var c = lexerAdvance(self);
    switch (c) {
        'n' => return '\n',
        't' => return '\t',
        'r' => return '\r',
        '\\' => return '\\',
        '"' => return '"',
        '\'' => return '\'',
        '0' => return @intCast(u8, 0),
        'x' => return lexerParseHexEscape(self),
        else => {
            const s_unesc: []const u8 = "unrecognized escape sequence";
            diag_mod.diagnosticCollectorAdd(self.diag, 1, @intCast(u16, @enumToInt(ErrorCode.WARN_1010_UNRECOGNIZED_ESCAPE)), self.file_id, @intCast(u32, self.pos - 2), @intCast(u32, self.pos), s_unesc);
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

        var digit: u64 = 0;
        var found_digit = true;
        if (c >= '0' and c <= '9') {
            digit = @intCast(u64, c - '0');
        } else if (c >= 'a' and c <= 'f') {
            digit = @intCast(u64, c - 'a' + 10);
        } else if (c >= 'A' and c <= 'F') {
            digit = @intCast(u64, c - 'A' + 10);
        } else {
            found_digit = false;
        }
        if (!found_digit) break;

        var base_u64 = @intCast(u64, @intCast(u32, base));
        if (digit >= base_u64) break;
        var max_u64: u64 = @intCast(u64, 0);
        max_u64 -= 1;
        var max_before_mul = max_u64 / base_u64;
        if (result > max_before_mul) return max_u64;
        result = result * base_u64;
        var after_mul = result;
        if (after_mul > max_u64 - digit) return max_u64;
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

const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const TokenValue = token_mod.TokenValue;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const ErrorCode = @import("diagnostics.zig").ErrorCode;
const diag_mod = @import("diagnostics.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const ga_mod = @import("growable_array.zig");
const U8ArrayList = ga_mod.U8ArrayList;

fn assertEqBool(actual: bool, expected: bool, line: u32) void {
    if (actual != expected) {
        var fmt_buf: [12]u8 = undefined;
        const s_fail: []const u8 = "FAIL line ";
        pal.stderr_write(s_fail);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 12));
        const s_exp: []const u8 = ": expected ";
        pal.stderr_write(s_exp);
        const str_true: []const u8 = "true";
        const str_false: []const u8 = "false";
        if (expected) pal.stderr_write(str_true) else pal.stderr_write(str_false);
        const s_got: []const u8 = ", got ";
        pal.stderr_write(s_got);
        if (actual) pal.stderr_write(str_true) else pal.stderr_write(str_false);
        const s_nl: []const u8 = "\n";
        pal.stderr_write(s_nl);
    }
}

fn assertEqU32(actual: u32, expected: u32, line: u32) void {
    if (actual != expected) {
        var fmt_buf: [12]u8 = undefined;
        const s_fail: []const u8 = "FAIL line ";
        pal.stderr_write(s_fail);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 12));
        const s_exp: []const u8 = ": expected ";
        pal.stderr_write(s_exp);
        pal.stderr_write(formatU32(expected, fmt_buf[0..], 12));
        const s_got: []const u8 = ", got ";
        pal.stderr_write(s_got);
        pal.stderr_write(formatU32(actual, fmt_buf[0..], 12));
        const s_nl: []const u8 = "\n";
        pal.stderr_write(s_nl);
    }
}

fn assertEqU8(actual: u8, expected: u8, line: u32) void {
    if (actual != expected) {
        var fmt_buf: [12]u8 = undefined;
        const s_fail: []const u8 = "FAIL line ";
        pal.stderr_write(s_fail);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 12));
        const s_msg: []const u8 = ": expected char\n";
        pal.stderr_write(s_msg);
    }
}

fn assertEqTokenKind(actual: TokenKind, expected: TokenKind, line: u32) void {
    if (actual != expected) {
        var fmt_buf: [12]u8 = undefined;
        const msg1: []const u8 = "FAIL line ";
        pal.stderr_write(msg1);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 12));
        const msg2: []const u8 = ": token kind mismatch\n";
        pal.stderr_write(msg2);
    }
}

fn formatU32(val: u32, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + v % 10);
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len];
}

pub fn lexerRunAllTests() void {
    const msg1: []const u8 = "Running lexer tests...\n";
    pal.stderr_write(msg1);
    lexerTestHelpers();
    lexerTestSkipWhitespaceAndComments();
    lexerTestOperators();
    lexerTestScanNumber();
    lexerTestScanString();
    lexerTestScanChar();
    lexerTestIdentifierKeywords();
    lexerTestBuiltinIdentifier();
    lexerTestDiagnostics();
    const msg2: []const u8 = "All lexer tests passed.\n";
    pal.stderr_write(msg2);
}

fn lexerTestHelpers() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const test_src: []const u8 = "abc";
    var lexer = lexerInit(test_src, 0, &interner, &diag, &sand);
    assertEqBool(lexerIsAtEnd(&lexer), false, @intCast(u32, 0));
    assertEqU32(@intCast(u32, lexer.pos), 0, @intCast(u32, 0));
    assertEqU32(lexer.line, 1, @intCast(u32, 0));
    assertEqU32(lexer.col, 1, @intCast(u32, 0));

    assertEqU8(lexerAdvance(&lexer), 'a', @intCast(u32, 0));
    assertEqU8(lexerPeek(&lexer), 'b', @intCast(u32, 0));
    assertEqU8(lexerPeekN(&lexer, 1), 'c', @intCast(u32, 0));
    assertEqBool(lexerIsAtEnd(&lexer), false, @intCast(u32, 0));
    assertEqU8(lexerAdvance(&lexer), 'b', @intCast(u32, 0));
    assertEqU8(lexerAdvance(&lexer), 'c', @intCast(u32, 0));
    assertEqBool(lexerIsAtEnd(&lexer), true, @intCast(u32, 0));
    assertEqU8(lexerAdvance(&lexer), 0, @intCast(u32, 0));
    assertEqU8(lexerPeek(&lexer), 0, @intCast(u32, 0));

    const s_ab: []const u8 = "ab";
    var lexer2 = lexerInit(s_ab, 0, &interner, &diag, &sand);
    assertEqBool(lexerMatch(&lexer2, 'a'), true, @intCast(u32, 0));
    assertEqBool(lexerMatch(&lexer2, 'x'), false, @intCast(u32, 0));
    assertEqBool(lexerMatch(&lexer2, 'b'), true, @intCast(u32, 0));

    const s_nl: []const u8 = "\n";
    var lexer3 = lexerInit(s_nl, 0, &interner, &diag, &sand);
    _ = lexerAdvance(&lexer3);
    assertEqU32(lexer3.line, 2, @intCast(u32, 0));
    assertEqU32(lexer3.col, 1, @intCast(u32, 0));
}

fn lexerTestSkipWhitespaceAndComments() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_spaces: []const u8 = "  \t  abc";
    var lexer = lexerInit(s_spaces, 0, &interner, &diag, &sand);
    lexerSkipWSC(&lexer);
    assertEqU8(lexerPeek(&lexer), 'a', @intCast(u32, 0));
}

fn lexerTestOperators() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_parens: []const u8 = "()[]{}";
    var l1 = lexerInit(s_parens, 0, &interner, &diag, &sand);
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.lparen, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.rparen, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.lbracket, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.rbracket, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.lbrace, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.rbrace, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l1).kind, TokenKind.eof, @intCast(u32, 0));

    const s_ops: []const u8 = "+-*/%&|^~!?;:,";
    var l2 = lexerInit(s_ops, 0, &interner, &diag, &sand);
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.plus, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.minus, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.star, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.slash, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.percent, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.ampersand, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.pipe, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.caret, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.tilde, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.bang, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.question_mark, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.semicolon, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.colon, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l2).kind, TokenKind.comma, @intCast(u32, 0));

    const s_compound: []const u8 = ".. ... .{ .* == => != <= >= << >> += -= *= /= %= &= |= ^= <<= >>=";
    var l3 = lexerInit(s_compound, 0, &interner, &diag, &sand);
    assertEqTokenKind(lexerNextToken(&l3).kind, TokenKind.dot_dot, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l3).kind, TokenKind.dot_dot_dot, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l3).kind, TokenKind.dot_lbrace, @intCast(u32, 0));
    assertEqTokenKind(lexerNextToken(&l3).kind, TokenKind.dot_star, @intCast(u32, 0));
}

fn lexerTestScanNumber() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_dec: []const u8 = "42";
    var l1 = lexerInit(s_dec, 0, &interner, &diag, &sand);
    var t1 = lexerNextToken(&l1);
    assertEqTokenKind(t1.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU32(@intCast(u32, t1.span_start), 0, @intCast(u32, 0));
    assertEqU32(@intCast(u32, t1.span_len), 2, @intCast(u32, 0));

    const s_hex: []const u8 = "0xFF";
    var l2 = lexerInit(s_hex, 0, &interner, &diag, &sand);
    var t2 = lexerNextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.integer_literal, @intCast(u32, 0));

    const s_bin: []const u8 = "0b1010";
    var l3 = lexerInit(s_bin, 0, &interner, &diag, &sand);
    var t3 = lexerNextToken(&l3);
    assertEqTokenKind(t3.kind, TokenKind.integer_literal, @intCast(u32, 0));

    const s_oct: []const u8 = "0o77";
    var l4 = lexerInit(s_oct, 0, &interner, &diag, &sand);
    var t4 = lexerNextToken(&l4);
    assertEqTokenKind(t4.kind, TokenKind.integer_literal, @intCast(u32, 0));

    const s_float: []const u8 = "3.14";
    var l5 = lexerInit(s_float, 0, &interner, &diag, &sand);
    var t5 = lexerNextToken(&l5);
    assertEqTokenKind(t5.kind, TokenKind.float_literal, @intCast(u32, 0));

    const s_sci: []const u8 = "1.5e10";
    var l6 = lexerInit(s_sci, 0, &interner, &diag, &sand);
    var t6 = lexerNextToken(&l6);
    assertEqTokenKind(t6.kind, TokenKind.float_literal, @intCast(u32, 0));
}

fn lexerTestScanString() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_hello: []const u8 = "\"hello\"";
    var l1 = lexerInit(s_hello, 0, &interner, &diag, &sand);
    var t1 = lexerNextToken(&l1);
    assertEqTokenKind(t1.kind, TokenKind.string_literal, @intCast(u32, 0));

    const s_esc: []const u8 = "\"hello\\nworld\"";
    var l2 = lexerInit(s_esc, 0, &interner, &diag, &sand);
    var t2 = lexerNextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.string_literal, @intCast(u32, 0));

    const s_unterm: []const u8 = "\"unterminated";
    var l3 = lexerInit(s_unterm, 0, &interner, &diag, &sand);
    var t3 = lexerNextToken(&l3);
    assertEqTokenKind(t3.kind, TokenKind.err_token, @intCast(u32, 0));
}

fn lexerTestScanChar() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_char: []const u8 = "'a'";
    var l1 = lexerInit(s_char, 0, &interner, &diag, &sand);
    var t1 = lexerNextToken(&l1);
    assertEqTokenKind(t1.kind, TokenKind.char_literal, @intCast(u32, 0));

    const s_cesc: []const u8 = "'\\n'";
    var l2 = lexerInit(s_cesc, 0, &interner, &diag, &sand);
    var t2 = lexerNextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.char_literal, @intCast(u32, 0));

    const s_cempty: []const u8 = "''";
    var l3 = lexerInit(s_cempty, 0, &interner, &diag, &sand);
    var t3 = lexerNextToken(&l3);
    assertEqTokenKind(t3.kind, TokenKind.char_literal, @intCast(u32, 0));
}

fn lexerTestIdentifierKeywords() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_under: []const u8 = "_";
    var l1 = lexerInit(s_under, 0, &interner, &diag, &sand);
    var t1 = lexerNextToken(&l1);
    assertEqTokenKind(t1.kind, TokenKind.underscore, @intCast(u32, 0));

    const s_ident: []const u8 = "myVar";
    var l2 = lexerInit(s_ident, 0, &interner, &diag, &sand);
    var t2 = lexerNextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.identifier, @intCast(u32, 0));

    const s_kw_const: []const u8 = "const";
    var l3 = lexerInit(s_kw_const, 0, &interner, &diag, &sand);
    var t3 = lexerNextToken(&l3);
    assertEqTokenKind(t3.kind, TokenKind.kw_const, @intCast(u32, 0));

    const s_kw_fn: []const u8 = "fn";
    var l4 = lexerInit(s_kw_fn, 0, &interner, &diag, &sand);
    var t4 = lexerNextToken(&l4);
    assertEqTokenKind(t4.kind, TokenKind.kw_fn, @intCast(u32, 0));
}

fn lexerTestBuiltinIdentifier() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_sizeof: []const u8 = "@sizeOf";
    var l1 = lexerInit(s_sizeof, 0, &interner, &diag, &sand);
    var t1 = lexerNextToken(&l1);
    assertEqTokenKind(t1.kind, TokenKind.builtin_identifier, @intCast(u32, 0));

    const s_bare_at: []const u8 = "@";
    var l2 = lexerInit(s_bare_at, 0, &interner, &diag, &sand);
    var t2 = lexerNextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.err_token, @intCast(u32, 0));
}

fn lexerTestDiagnostics() void {
    var arena_buf: [8192]u8 = undefined;
    var sand = alloc_mod.sandInit(arena_buf[0..]);
    var interner = interner_mod.stringInternerInit(&sand, 4);
    var source_man = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);

    const s_backtick: []const u8 = "`";
    var l1 = lexerInit(s_backtick, 0, &interner, &diag, &sand);
    var t1 = lexerNextToken(&l1);
    assertEqTokenKind(t1.kind, TokenKind.err_token, @intCast(u32, 0));

    const s_at_backtick: []const u8 = "@`";
    var l2 = lexerInit(s_at_backtick, 0, &interner, &diag, &sand);
    var t2 = lexerNextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.err_token, @intCast(u32, 0));
}

const pal = @import("pal.zig");
const interner_mod = @import("string_interner.zig");
const sm_mod = @import("source_manager.zig");
