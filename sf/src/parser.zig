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
const AstKind = @import("ast.zig").AstKind;
const ast_mod = @import("ast.zig");
const string_interner_mod = @import("string_interner.zig");

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
        var expect_msg: []const u8 = "bad tok";
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

pub fn parserParseExprPrec(self: *Parser, min_prec: Prec) ParserError!u32 {
    var lhs = try parserParsePrimary(self);

    while (true) {
        var tok = parserPeek(self);
        var has_info: u8 = 0;
        var info: OpInfo = undefined;
        if (getInfixInfo(tok.kind)) |val| {
            info = val;
            has_info = 1;
        }
        if (has_info == 0) break;
        if (precToInt(info.prec) < precToInt(min_prec)) break;

        _ = parserAdvance(self);

        var next_min: Prec = undefined;
        if (info.right_assoc) {
            next_min = info.prec;
        } else {
            next_min = precFromInt(precToInt(info.prec) + 1);
        }

        var rhs: u32 = undefined;
        if (tok.kind == TokenKind.kw_catch) {
            return error.UnexpectedToken;
        } else if (tok.kind == TokenKind.kw_orelse) {
            return error.UnexpectedToken;
        } else {
            rhs = try parserParseExprPrec(self, next_min);
        }

        lhs = try parserAddBinary(self, tok, lhs, rhs);
    }
    return lhs;
}

fn parserAddBinary(self: *Parser, tok: Token, lhs: u32, rhs: u32) ParserError!u32 {
    var kind: AstKind = undefined;
    var found: u8 = 0;
    switch (tok.kind) {
        TokenKind.plus => { kind = AstKind.add; found = 1; },
        TokenKind.minus => { kind = AstKind.sub; found = 1; },
        TokenKind.star => { kind = AstKind.mul; found = 1; },
        TokenKind.slash => { kind = AstKind.div; found = 1; },
        TokenKind.percent => { kind = AstKind.mod_op; found = 1; },
        TokenKind.ampersand => { kind = AstKind.bit_and; found = 1; },
        TokenKind.pipe => { kind = AstKind.bit_or; found = 1; },
        TokenKind.caret => { kind = AstKind.bit_xor; found = 1; },
        TokenKind.shl => { kind = AstKind.shl; found = 1; },
        TokenKind.shr => { kind = AstKind.shr; found = 1; },
        TokenKind.kw_and => { kind = AstKind.bool_and; found = 1; },
        TokenKind.kw_or => { kind = AstKind.bool_or; found = 1; },
        TokenKind.eq_eq => { kind = AstKind.cmp_eq; found = 1; },
        TokenKind.bang_eq => { kind = AstKind.cmp_ne; found = 1; },
        TokenKind.less => { kind = AstKind.cmp_lt; found = 1; },
        TokenKind.less_eq => { kind = AstKind.cmp_le; found = 1; },
        TokenKind.greater => { kind = AstKind.cmp_gt; found = 1; },
        TokenKind.greater_eq => { kind = AstKind.cmp_ge; found = 1; },
        TokenKind.eq => { kind = AstKind.assign; found = 1; },
        TokenKind.plus_eq => { kind = AstKind.add_assign; found = 1; },
        TokenKind.minus_eq => { kind = AstKind.sub_assign; found = 1; },
        TokenKind.star_eq => { kind = AstKind.mul_assign; found = 1; },
        TokenKind.slash_eq => { kind = AstKind.div_assign; found = 1; },
        TokenKind.percent_eq => { kind = AstKind.mod_assign; found = 1; },
        TokenKind.shl_eq => { kind = AstKind.shl_assign; found = 1; },
        TokenKind.shr_eq => { kind = AstKind.shr_assign; found = 1; },
        TokenKind.ampersand_eq => { kind = AstKind.and_assign; found = 1; },
        TokenKind.pipe_eq => { kind = AstKind.or_assign; found = 1; },
        TokenKind.caret_eq => { kind = AstKind.xor_assign; found = 1; },
        else => {},
    }
    if (found == 0) {
        var add_msg: []const u8 = "bad op";
        parserAddError(self, tok, add_msg);
        return error.UnexpectedToken;
    }
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start, end, lhs, rhs, 0, 0);
}

pub fn parserParsePrimary(self: *Parser) ParserError!u32 {
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.integer_literal) return parserParseIntLiteral(self);
    if (tok.kind == TokenKind.float_literal) return parserParseFloatLiteral(self);
    if (tok.kind == TokenKind.string_literal) return parserParseStringLiteral(self);
    if (tok.kind == TokenKind.char_literal) return parserParseCharLiteral(self);
    if (tok.kind == TokenKind.kw_true) return parserParseBoolLiteral(self);
    if (tok.kind == TokenKind.kw_false) return parserParseBoolLiteral(self);
    if (tok.kind == TokenKind.kw_null) return parserParseSingleToken(self, AstKind.null_literal);
    if (tok.kind == TokenKind.kw_undefined) return parserParseSingleToken(self, AstKind.undefined_literal);
    if (tok.kind == TokenKind.kw_unreachable) return parserParseSingleToken(self, AstKind.unreachable_expr);
    if (tok.kind == TokenKind.identifier) return parserParseIdentExpr(self);
    if (tok.kind == TokenKind.builtin_identifier) return parserParseBuiltinCall(self);
    if (tok.kind == TokenKind.kw_error) return parserParseErrorLiteral(self);
    if (tok.kind == TokenKind.minus) return parserParsePrefixUnary(self, AstKind.negate);
    if (tok.kind == TokenKind.bang) return parserParsePrefixUnary(self, AstKind.bool_not);
    if (tok.kind == TokenKind.tilde) return parserParsePrefixUnary(self, AstKind.bit_not);
    if (tok.kind == TokenKind.ampersand) return parserParsePrefixUnary(self, AstKind.address_of);
    if (tok.kind == TokenKind.kw_try) return parserParseTryExpr(self);
    if (tok.kind == TokenKind.lparen) return parserParseGroupedExpr(self);
    if (tok.kind == TokenKind.dot_lbrace) return parserParseAnonymousLiteral(self);
    if (tok.kind == TokenKind.dot) return parserParseEnumLiteral(self);
    if (tok.kind == TokenKind.kw_if) return parserParseIfExpr(self);
    if (tok.kind == TokenKind.kw_switch) return parserParseSwitchExpr(self);
    var primary_msg: []const u8 = "bad expr";
    parserAddError(self, tok, primary_msg);
    return error.UnexpectedToken;
}

fn parserParseIntLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddIntLiteral(self.store, tok.value.int_val, tok.span_start, end);
}

fn parserParseFloatLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddFloatLiteral(self.store, tok.value.float_val, tok.span_start, end);
}

fn parserParseStringLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var pt = ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
    var text = parserTokenText(self, pt);
    var id = string_interner_mod.stringInternerIntern(self.interner, text);
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddStringLiteral(self.store, id, tok.span_start, end);
}

fn parserParseCharLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.char_literal, 0, tok.span_start, end, 0, 0, 0, 0);
}

fn parserParseBoolLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var val: u8 = 0;
    if (tok.kind == TokenKind.kw_true) val = 1;
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.bool_literal, val, tok.span_start, end, 0, 0, 0, 0);
}

fn parserParseSingleToken(self: *Parser, kind: AstKind) ParserError!u32 {
    var tok = parserAdvance(self);
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start, end, 0, 0, 0, 0);
}

fn parserParseIdentExpr(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var pt = ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
    var id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    var end = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddIdentifier(self.store, AstKind.ident_expr, id, tok.span_start, end);
}

fn parserParsePrefixUnary(self: *Parser, kind: AstKind) ParserError!u32 {
    var tok = parserAdvance(self);
    var operand = try parserParseExprPrec(self, Prec.prefix);
    var end = tok.span_start + @intCast(u32, tok.span_len);
    _ = operand;
    _ = end;
    return error.UnexpectedToken;
}

fn parserParseGroupedExpr(self: *Parser) ParserError!u32 {
    _ = parserAdvance(self);
    var inner = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.rparen);
    return inner;
}

fn parserParseBuiltinCall(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
}

fn parserParseErrorLiteral(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
}

fn parserParseTryExpr(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
}

fn parserParseAnonymousLiteral(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
}

fn parserParseEnumLiteral(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
}

fn parserParseIfExpr(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
}

fn parserParseSwitchExpr(self: *Parser) ParserError!u32 {
    return error.UnexpectedToken;
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
