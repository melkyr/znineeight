pub const ParserError = error {
    UnexpectedToken,
};

const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const AstStore = @import("ast.zig").AstStore;
const Sand = @import("allocator.zig").Sand;
const diag_mod = @import("diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const StringInterner = @import("string_interner.zig").StringInterner;
const U32ArrayList = @import("growable_array.zig").U32ArrayList;
const u32ArrayListInit = @import("growable_array.zig").u32ArrayListInit;

pub const ParseToken = struct {
    kind: TokenKind,
    span_start: u32,
    span_len: u16,
};

pub const Parser = struct {
    tokens_ptr: [*]Token,
    tokens_len: usize,
    source_ptr: [*]u8,
    source_len: usize,
    pos: usize,
    store: *AstStore,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    allocator: *Sand,
    child_buf_items: [*]u32,
    child_buf_len: usize,
    child_buf_capacity: usize,
};

pub fn parserInit(tokens: []const Token, source: []const u8, store: *AstStore, interner: *StringInterner, diag: *DiagnosticCollector, alloc: *Sand) Parser {
    var t_ptr = @ptrCast([*]Token, tokens.ptr);
    return Parser{
        .tokens_ptr = t_ptr,
        .tokens_len = tokens.len,
        .source_ptr = @ptrCast([*]u8, source.ptr),
        .source_len = source.len,
        .pos = @intCast(usize, 0),
        .store = store,
        .interner = interner,
        .diag = diag,
        .allocator = alloc,
        .child_buf_items = undefined,
        .child_buf_len = @intCast(usize, 0),
        .child_buf_capacity = @intCast(usize, 0),
    };
}

pub fn parserTokenText(self: *Parser, tok: ParseToken) []const u8 {
    var start = @intCast(usize, tok.span_start);
    var end = start + @intCast(usize, tok.span_len);
    return self.source_ptr[start..end];
}

pub fn parserPeek(self: *Parser) Token {
    if (self.pos >= self.tokens_len) return self.tokens_ptr[self.tokens_len - 1];
    return self.tokens_ptr[self.pos];
}

pub fn parserPeekN(self: *Parser, n: usize) Token {
    var idx = self.pos + n;
    if (idx >= self.tokens_len) return self.tokens_ptr[self.tokens_len - 1];
    return self.tokens_ptr[idx];
}

pub fn parserAdvance(self: *Parser) Token {
    var tok = parserPeek(self);
    if (self.pos < self.tokens_len) self.pos += 1;
    return tok;
}

pub fn parserExpect(self: *Parser, kind: TokenKind) ParserError!ParseToken {
    var tok = parserPeek(self);
    if (tok.kind != kind) {
        var expect_msg: []const u8 = "expected token";
        parserAddError(self, tok, expect_msg);
        return error.UnexpectedToken;
    }
    // consume via advanceTok and return ParseToken
    if (self.pos < self.tokens_len) self.pos += 1;
    return ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
}

pub fn parserAddError(self: *Parser, tok: Token, msg: []const u8) void {
    diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 2000),
        @intCast(u32, 0), tok.span_start, tok.span_start + @intCast(u32, tok.span_len), msg);
}

pub fn parserSynchronize(self: *Parser) void {
    while (self.pos < self.tokens_len) {
        var k = self.tokens_ptr[self.pos].kind;
        if (k == TokenKind.semicolon or k == TokenKind.rbrace or k == TokenKind.kw_fn or
            k == TokenKind.kw_const or k == TokenKind.kw_var or k == TokenKind.kw_pub or
            k == TokenKind.kw_test or k == TokenKind.eof) return;
        self.pos += 1;
    }
}

pub const Prec = enum(u8) {
    none = 0,
    assignment = 1,
    prec_orelse = 2,
    prec_catch = 3,
    bool_or = 4,
    bool_and = 5,
    comparison = 6,
    bit_or = 7,
    bit_xor = 8,
    bit_and = 9,
    shift = 10,
    additive = 11,
    multiply = 12,
    prefix = 13,
    postfix = 14,
};

pub fn precToInt(p: Prec) u8 {
    return @intCast(u8, @enumToInt(p));
}

pub fn precFromInt(v: u8) Prec {
    return @intToEnum(Prec, v);
}

pub const OpInfo = struct {
    prec: Prec,
    right_assoc: bool,
};

pub fn getInfixInfo(kind: TokenKind) ?OpInfo {
    if (kind == TokenKind.eq or kind == TokenKind.plus_eq or
        kind == TokenKind.minus_eq or kind == TokenKind.star_eq or
        kind == TokenKind.slash_eq or kind == TokenKind.percent_eq or
        kind == TokenKind.shl_eq or kind == TokenKind.shr_eq or
        kind == TokenKind.ampersand_eq or kind == TokenKind.pipe_eq or
        kind == TokenKind.caret_eq) return OpInfo{ .prec = Prec.assignment, .right_assoc = true };

    if (kind == TokenKind.kw_orelse) return OpInfo{ .prec = Prec.prec_orelse, .right_assoc = true };
    if (kind == TokenKind.kw_catch) return OpInfo{ .prec = Prec.prec_catch, .right_assoc = true };

    if (kind == TokenKind.kw_or) return OpInfo{ .prec = Prec.bool_or, .right_assoc = false };
    if (kind == TokenKind.kw_and) return OpInfo{ .prec = Prec.bool_and, .right_assoc = false };

    if (kind == TokenKind.eq_eq or kind == TokenKind.bang_eq or
        kind == TokenKind.less or kind == TokenKind.less_eq or
        kind == TokenKind.greater or kind == TokenKind.greater_eq)
        return OpInfo{ .prec = Prec.comparison, .right_assoc = false };

    if (kind == TokenKind.pipe) return OpInfo{ .prec = Prec.bit_or, .right_assoc = false };
    if (kind == TokenKind.caret) return OpInfo{ .prec = Prec.bit_xor, .right_assoc = false };
    if (kind == TokenKind.ampersand) return OpInfo{ .prec = Prec.bit_and, .right_assoc = false };
    if (kind == TokenKind.shl or kind == TokenKind.shr) return OpInfo{ .prec = Prec.shift, .right_assoc = false };
    if (kind == TokenKind.plus or kind == TokenKind.minus) return OpInfo{ .prec = Prec.additive, .right_assoc = false };
    if (kind == TokenKind.star or kind == TokenKind.slash or kind == TokenKind.percent) return OpInfo{ .prec = Prec.multiply, .right_assoc = false };

    return null;
}
