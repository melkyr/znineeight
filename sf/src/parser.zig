pub const ParserError = error {
    UnexpectedToken,
};

const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const AstStore = @import("ast.zig").AstStore;
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const diag_mod = @import("diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const StringInterner = @import("string_interner.zig").StringInterner;
const U32ArrayList = @import("growable_array.zig").U32ArrayList;
const u32ArrayListInit = @import("growable_array.zig").u32ArrayListInit;
const AstKind = @import("ast.zig").AstKind;
const FnProto = @import("ast.zig").FnProto;
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
    last_end: u32,
    case_buf_items: [*]u32,
    case_buf_len: usize,
    case_buf_capacity: usize,
    builtin_import_id: u32,
    catch_capture: u32,
    expr_depth: u32,
};

pub fn parserInit(tokens: []const Token, source: []const u8, store: *AstStore, interner: *StringInterner, diag: *DiagnosticCollector, alloc: *Sand) Parser {
    var t_ptr = @ptrCast([*]Token, tokens.ptr);
    var import_s: []const u8 = "import";
    var import_id = string_interner_mod.stringInternerIntern(interner, import_s);
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
        .last_end = @intCast(u32, 0),
        .case_buf_items = undefined,
        .case_buf_len = @intCast(usize, 0),
        .case_buf_capacity = @intCast(usize, 0),
        .catch_capture = @intCast(u32, 0),
        .expr_depth = @intCast(u32, 0),
        .builtin_import_id = import_id,
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
    self.last_end = tok.span_start + @intCast(u32, tok.span_len);
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
    self.expr_depth += 1;
    if (self.expr_depth > 12) {
        var msg: []const u8 = "max expression recursion depth exceeded";
        @panic(msg);
    }
    defer self.expr_depth -= 1;
    var lhs = try parserParsePrimary(self);
    lhs = try parserParsePostfixChain(self, lhs);

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
            rhs = try parserParseCatchRHS(self, next_min);
        } else if (tok.kind == TokenKind.kw_orelse) {
            rhs = try parserParseOrelseRHS(self, next_min);
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
        TokenKind.kw_catch => { kind = AstKind.catch_expr; found = 1; },
        TokenKind.kw_orelse => { kind = AstKind.orelse_expr; found = 1; },
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
    if (tok.kind == TokenKind.underscore) return parserParseIdentExpr(self);
    if (tok.kind == TokenKind.identifier) {
        if (parserPeekN(self, 1).kind == TokenKind.colon and parserPeekN(self, 2).kind == TokenKind.lbrace) {
            return parserParseLabeledBlockExpr(self);
        }
        return parserParseIdentExpr(self);
    }
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
    if (tok.kind == TokenKind.lbracket) return parserParseArrayLiteral(self);
    if (tok.kind == TokenKind.kw_struct) return parserParseStructType(self);
    if (tok.kind == TokenKind.kw_enum) return parserParseEnumType(self);
    if (tok.kind == TokenKind.kw_union) return parserParseUnionType(self);
    if (tok.kind == TokenKind.kw_return) return parserParseReturnExpr(self);
    if (tok.kind == TokenKind.kw_break) return parserParseBreakExpr(self);
    if (tok.kind == TokenKind.kw_continue) return parserParseContinueExpr(self);
    if (tok.kind == TokenKind.lbrace) return parserParseBlock(self);
    var primary_msg: []const u8 = "bad expr";
    parserAddError(self, tok, primary_msg);
    return error.UnexpectedToken;
}

pub fn parserParsePostfixChain(self: *Parser, base: u32) ParserError!u32 {
    var node = base;
    while (true) {
        var tok = parserPeek(self);
        if (tok.kind == TokenKind.dot) {
            node = try parserParseDotAccess(self, node);
        } else if (tok.kind == TokenKind.lbracket) {
            node = try parserParseIndexOrSlice(self, node);
        } else if (tok.kind == TokenKind.lparen) {
            node = try parserParseFnCall(self, node);
        } else if (tok.kind == TokenKind.lbrace) {
            node = try parserParseStructInit(self, node);
        } else {
            break;
        }
    }
    return node;
}

fn parserParseDotAccess(self: *Parser, base: u32) ParserError!u32 {
    _ = parserAdvance(self);
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.star) {
        _ = parserAdvance(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.deref, 0,
            tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
            base, 0, 0, 0);
    }
    var pt = ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    _ = parserAdvance(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.field_access, 0,
        pt.span_start, pt.span_start + @intCast(u32, pt.span_len),
        base, 0, 0, name_id);
}

fn parserParseIndexOrSlice(self: *Parser, base: u32) ParserError!u32 {
    _ = parserAdvance(self);
    var first = try parserParseExprPrec(self, Prec.none);
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.dot_dot) {
        _ = parserAdvance(self);
        var last = try parserParseExprPrec(self, Prec.none);
        _ = try parserExpect(self, TokenKind.rbracket);
        return ast_mod.astStoreAddNode(self.store, AstKind.slice_expr, 0,
            tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
            base, first, last, 0);
    }
    _ = try parserExpect(self, TokenKind.rbracket);
    return ast_mod.astStoreAddNode(self.store, AstKind.index_access, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        base, first, 0, 0);
}

fn parserParseFnCall(self: *Parser, base: u32) ParserError!u32 {
    var lparen = parserAdvance(self);
    if (parserPeek(self).kind == TokenKind.rparen) {
        var rparen = parserAdvance(self);
        var end = rparen.span_start + @intCast(u32, rparen.span_len);
        return ast_mod.astStoreAddNode(self.store, AstKind.fn_call, 0, lparen.span_start, end, base, 0, 0, 0);
    }
    while (true) {
        var arg = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
        if (parserPeek(self).kind == TokenKind.rparen) break;
        _ = try parserExpect(self, TokenKind.comma);
    }
    var rparen = parserAdvance(self);
    var end = rparen.span_start + @intCast(u32, rparen.span_len);
    var payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    self.child_buf_len = 0;
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_call, 0, lparen.span_start, end, base, 0, 0, payload);
}

fn parserParseCatchRHS(self: *Parser, next_min: Prec) ParserError!u32 {
    self.catch_capture = @intCast(u32, 0);
    var ptok = parserPeek(self);
    if (ptok.kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var name_tok = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.pipe);
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, name_tok));
        self.catch_capture = ast_mod.astStoreAddNode(self.store, AstKind.payload_capture, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            0, 0, 0, name_id);
    }
    if (parserPeek(self).kind == TokenKind.lbrace) {
        var block_node = try parserParseBlock(self);
        return block_node;
    }
    return parserParseExprPrec(self, next_min);
}

fn parserParseOrelseRHS(self: *Parser, next_min: Prec) ParserError!u32 {
    if (parserPeek(self).kind == TokenKind.lbrace) {
        return parserParseBlock(self);
    }
    return parserParseExprPrec(self, next_min);
}

fn parserParseFieldInitListNamed(self: *Parser) ParserError!u32 {
    var saved_child_len = self.child_buf_len;
    self.child_buf_len = 0;
    while (parserPeek(self).kind == TokenKind.dot) {
        _ = parserAdvance(self);
        var name_tok = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.eq);
        var val = try parserParseExprPrec(self, Prec.none);
        var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
        var field = ast_mod.astStoreAddNode(self.store, AstKind.field_init, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            val, 0, 0, name_id);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len,
            &self.child_buf_capacity, self.allocator, field);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (self.child_buf_len > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    }
    self.child_buf_len = saved_child_len;
    return payload;
}

fn parserParseStructInit(self: *Parser, base: u32) ParserError!u32 {
    var lbrace = parserAdvance(self);
    var payload = try parserParseFieldInitListNamed(self);
    var end_pos = self.last_end;
    return ast_mod.astStoreAddNode(self.store, AstKind.struct_init, 0,
        lbrace.span_start, end_pos, base, 0, 0, payload);
}

fn u32ArrayListAppendInner(items: *[*]u32, len: *usize, capacity: *usize, arena: *Sand, value: u32) void {
    if (len.* >= capacity.*) {
        var new_cap = capacity.*;
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (new_cap < len.* * 2) new_cap = len.* * 2;
        var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
        var new_items_p = @ptrCast([*]u32, raw);
        for (items.*[0..len.*]) |item, i| {
            new_items_p[i] = item;
        }
        items.* = new_items_p;
        capacity.* = new_cap;
    }
    items.*[len.*] = value;
    len.* += 1;
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
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start,
        end, operand, 0, 0, 0);
}

fn parserParseGroupedExpr(self: *Parser) ParserError!u32 {
    _ = parserAdvance(self);
    var inner = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.rparen);
    return inner;
}

fn parserParseBuiltinCall(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    if (tok.value.string_id == self.builtin_import_id) {
        return parserParseImportExpr(self, tok);
    }
    var id = tok.value.string_id;
    var end = tok.span_start + @intCast(u32, tok.span_len);
    _ = end;
    var lparen = parserPeek(self);
    if (lparen.kind != TokenKind.lparen) return error.UnexpectedToken;
    _ = parserAdvance(self);
    while (true) {
        var arg = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
        if (parserPeek(self).kind == TokenKind.rparen) break;
        _ = try parserExpect(self, TokenKind.comma);
    }
    var rparen = parserAdvance(self);
    end = rparen.span_start + @intCast(u32, rparen.span_len);
    var payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    self.child_buf_len = 0;
    return ast_mod.astStoreAddNode(self.store, AstKind.builtin_call, 0, tok.span_start, end, 0, 0, 0, payload);
}

fn parserParseImportExpr(self: *Parser, bi_tok: Token) ParserError!u32 {
    var lparen = parserPeek(self);
    if (lparen.kind != TokenKind.lparen) return error.UnexpectedToken;
    _ = parserAdvance(self);
    var path_tok = parserPeek(self);
    if (path_tok.kind != TokenKind.string_literal) return error.UnexpectedToken;
    var path_id = path_tok.value.string_id;
    _ = parserAdvance(self);
    var rparen = parserPeek(self);
    if (rparen.kind != TokenKind.rparen) return error.UnexpectedToken;
    var end_pos = rparen.span_start + @intCast(u32, rparen.span_len);
    _ = parserAdvance(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.import_expr, 0,
        bi_tok.span_start, end_pos, 0, 0, 0, path_id);
}

fn parserParseErrorLiteral(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.dot);
    var name_tok = try parserExpect(self, TokenKind.identifier);
    var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    var end = name_tok.span_start + @intCast(u32, name_tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.error_literal, 0,
        kw.span_start, end, 0, 0, 0, name_id);
}

fn parserParseTryExpr(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    var inner = try parserParseExprPrec(self, Prec.prefix);
    var end_pos: u32 = kw.span_start + @intCast(u32, kw.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.try_expr, 0,
        kw.span_start, end_pos, inner, 0, 0, 0);
}

fn parserParseAnonymousLiteral(self: *Parser) ParserError!u32 {
    var dot = parserAdvance(self);
    var peek = parserPeek(self);
    if (peek.kind == TokenKind.dot or peek.kind == TokenKind.rbrace) {
        var payload = try parserParseFieldInitListNamed(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.struct_init, 0,
            dot.span_start, self.last_end, 0, 0, 0, payload);
    }
    var saved_child_len = self.child_buf_len;
    self.child_buf_len = 0;
    while (parserPeek(self).kind != TokenKind.rbrace and parserPeek(self).kind != TokenKind.eof) {
        var val = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len,
            &self.child_buf_capacity, self.allocator, val);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (self.child_buf_len > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    }
    self.child_buf_len = saved_child_len;
    return ast_mod.astStoreAddNode(self.store, AstKind.tuple_literal, 0,
        dot.span_start, rbrace.span_start + @intCast(u32, rbrace.span_len),
        0, 0, 0, payload);
}

fn parserParseEnumLiteral(self: *Parser) ParserError!u32 {
    var dot = parserAdvance(self);
    var name_tok = try parserExpect(self, TokenKind.identifier);
    var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    var end_pos: u32 = name_tok.span_start + @intCast(u32, name_tok.span_len);
    return ast_mod.astStoreAddIdentifier(self.store, AstKind.enum_literal, name_id, dot.span_start, end_pos);
}

fn parserParseArrayLiteral(self: *Parser) ParserError!u32 {
    var tok = parserPeek(self);
    var type_node = try parserParseBracketType(self);
    if (parserPeek(self).kind != TokenKind.lbrace) {
        var a_sub: []const u8 = "expected '{' after array type";
        parserAddError(self, tok, a_sub);
        return error.UnexpectedToken;
    }
    _ = parserAdvance(self);
    var saved_child_len = self.child_buf_len;
    self.child_buf_len = 0;
    while (parserPeek(self).kind != TokenKind.rbrace and parserPeek(self).kind != TokenKind.eof) {
        var val = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len,
            &self.child_buf_capacity, self.allocator, val);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var gap: []const u8 = "";
    _ = gap;
    var payload: u32 = 0;
    if (self.child_buf_len > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store,
            self.child_buf_items[0..self.child_buf_len]);
    }
    self.child_buf_len = saved_child_len;
    return ast_mod.astStoreAddNode(self.store, AstKind.array_init, 0,
        tok.span_start, rbrace.span_start + @intCast(u32, rbrace.span_len),
        type_node, 0, 0, payload);
}

fn parserParseIfExpr(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var cond = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.rparen);
    var then_body = try parserParseExprPrec(self, Prec.none);
    var else_body: u32 = 0;
    if (parserPeek(self).kind == TokenKind.kw_else) {
        _ = parserAdvance(self);
        else_body = try parserParseExprPrec(self, Prec.none);
    }
    var end_pos: u32 = kw.span_start;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.if_expr, 0,
        kw.span_start, end_pos, cond, then_body, else_body, 0);
}

pub fn parserParseSwitchExpr(self: *Parser) ParserError!u32 {
    var kw_tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var cond: u32 = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.rparen);
    _ = try parserExpect(self, TokenKind.lbrace);

    self.child_buf_len = @intCast(usize, 0);
    while (true) {
        var tok = parserPeek(self);
        if (tok.kind == TokenKind.rbrace) break;
        if (tok.kind == TokenKind.eof) break;
        var prong = try parserParseSwitchProng(self);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, prong);
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);

    var payload: u32 = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    var end_pos: u32 = kw_tok.span_start + @intCast(u32, kw_tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.switch_expr, 0,
        kw_tok.span_start, end_pos, cond, 0, 0, payload);
}

fn parserParseSwitchProng(self: *Parser) ParserError!u32 {
    var start_tok = parserPeek(self);
    self.case_buf_len = @intCast(usize, 0);
    var is_else: u8 = 0;

    if (parserPeek(self).kind == TokenKind.kw_else) {
        _ = parserAdvance(self);
        is_else = 1;
    } else {
        while (true) {
            var item: u32 = try parserParseExprPrec(self, Prec.assignment);
            var range_kind: AstKind = AstKind.err;
            var end_item: u32 = 0;
            if (parserPeek(self).kind == TokenKind.dot_dot) {
                _ = parserAdvance(self);
                end_item = try parserParseExprPrec(self, Prec.assignment);
                range_kind = AstKind.range_exclusive;
            } else if (parserPeek(self).kind == TokenKind.dot_dot_dot) {
                _ = parserAdvance(self);
                end_item = try parserParseExprPrec(self, Prec.assignment);
                range_kind = AstKind.range_inclusive;
            }
            if (range_kind != AstKind.err) {
                var range_node = ast_mod.astStoreAddNode(self.store, range_kind, 0,
                    start_tok.span_start, start_tok.span_start + @intCast(u32, start_tok.span_len),
                    item, end_item, 0, 0);
                u32ArrayListAppendInner(&self.case_buf_items, &self.case_buf_len, &self.case_buf_capacity, self.allocator, range_node);
            } else {
                u32ArrayListAppendInner(&self.case_buf_items, &self.case_buf_len, &self.case_buf_capacity, self.allocator, item);
            }
            if (parserPeek(self).kind != TokenKind.comma) break;
            if (parserPeekN(self, 1).kind == TokenKind.fat_arrow) break;
            _ = parserAdvance(self);
        }
    }

    _ = try parserExpect(self, TokenKind.fat_arrow);

    var flags: u8 = 0;
    var capture_name: u32 = 0;
    if (parserPeek(self).kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var name_tok: ParseToken = undefined;
        if (parserPeek(self).kind == TokenKind.underscore) {
            name_tok = try parserExpect(self, TokenKind.underscore);
        } else {
            name_tok = try parserExpect(self, TokenKind.identifier);
        }
        _ = try parserExpect(self, TokenKind.pipe);
        var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        capture_name = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
        flags = 16;
    }
    if (is_else != 0) {
        flags = flags | 1;
    }

    var body: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.lbrace) {
        body = try parserParseBlock(self);
    } else {
        body = try parserParseExprPrec(self, Prec.assignment);
    }

    var items_payload: u32 = ast_mod.astStoreAddExtraChildren(self.store, self.case_buf_items[0..self.case_buf_len]);
    var end_pos: u32 = start_tok.span_start + @intCast(u32, start_tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.switch_prong, flags,
        start_tok.span_start, end_pos, body, 0, 0, items_payload);
}

pub fn parserParseType(self: *Parser) ParserError!u32 {
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.star) return parserParsePtrType(self);
    if (tok.kind == TokenKind.lbracket) return parserParseBracketType(self);
    if (tok.kind == TokenKind.question_mark) return parserParseOptionalType(self);
    if (tok.kind == TokenKind.bang) return parserParseErrorUnionType(self);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnType(self);
    if (tok.kind == TokenKind.kw_error) return parserParseErrorSetDecl(self);
    if (tok.kind == TokenKind.kw_struct) return parserParseStructType(self);
    if (tok.kind == TokenKind.kw_enum) return parserParseEnumType(self);
    if (tok.kind == TokenKind.kw_union) return parserParseUnionType(self);
    return parserParseTypeName(self);
}

fn parserParsePtrType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var flags: u8 = 0;
    if (parserPeek(self).kind == TokenKind.kw_const) {
        _ = parserAdvance(self);
        flags = 1;
    }
    var base = try parserParseType(self);
    var end_pos = base;
    _ = end_pos;
    return ast_mod.astStoreAddNode(self.store, AstKind.ptr_type, flags,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        base, 0, 0, 0);
}

fn parserParseBracketType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    if (parserPeek(self).kind == TokenKind.star) {
        _ = parserAdvance(self);
        _ = try parserExpect(self, TokenKind.rbracket);
        var flags: u8 = 0;
        if (parserPeek(self).kind == TokenKind.kw_const) {
            _ = parserAdvance(self);
            flags = 1;
        }
        var base = try parserParseType(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.many_ptr_type, flags,
            tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
            base, 0, 0, 0);
    }
    if (parserPeek(self).kind == TokenKind.rbracket) {
        _ = parserAdvance(self);
        var flags: u8 = 0;
        if (parserPeek(self).kind == TokenKind.kw_const) {
            _ = parserAdvance(self);
            flags = 1;
        }
        var base = try parserParseType(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.slice_type, flags,
            tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
            base, 0, 0, 0);
    }
    var size_expr = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.rbracket);
    var base = try parserParseType(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.array_type, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        base, size_expr, 0, 0);
}

fn parserParseOptionalType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var payload = try parserParseType(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.optional_type, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        payload, 0, 0, 0);
}

fn parserParseErrorUnionType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var payload = try parserParseType(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.error_union_type, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        payload, 0, 0, 0);
}

fn parserParseFnType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var param_buf: [64]u32 = undefined;
    var param_count: usize = 0;
    while (parserPeek(self).kind != TokenKind.rparen) {
        var p = try parserParseType(self);
        param_buf[param_count] = p;
        param_count += 1;
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rparen);
    var ret_type: u32 = 0;
    if (parserPeek(self).kind != TokenKind.lbrace and
        parserPeek(self).kind != TokenKind.semicolon and
        parserPeek(self).kind != TokenKind.eof and
        parserPeek(self).kind != TokenKind.rparen and
        parserPeek(self).kind != TokenKind.rbracket and
        parserPeek(self).kind != TokenKind.comma)
    {
        ret_type = try parserParseType(self);
    }
    var payload: u32 = 0;
    if (param_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, param_buf[0..param_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_type, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        ret_type, 0, 0, payload);
}

fn parserParseErrorSetDecl(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lbrace);
    var member_buf: [64]u32 = undefined;
    var member_count: usize = 0;
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var tag_tok = try parserExpect(self, TokenKind.identifier);
        var pt = ParseToken{ .kind = tag_tok.kind, .span_start = tag_tok.span_start, .span_len = tag_tok.span_len };
        var tag_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
        member_buf[member_count] = tag_id;
        member_count += 1;
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (member_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, member_buf[0..member_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.error_set_decl, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        0, 0, 0, payload);
}

fn parserParseStructType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lbrace);
    var fields_buf: [64]u32 = undefined;
    var fields_count: usize = 0;
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var name_tok = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.colon);
        var npt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, npt));
        var field_type = try parserParseType(self);
        var field_node = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            field_type, 0, 0, name_id);
        fields_buf[fields_count] = field_node;
        fields_count += 1;
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (fields_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, fields_buf[0..fields_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.struct_decl, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        0, 0, 0, payload);
}

fn parserParseEnumType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lbrace);
    var members_buf: [64]u32 = undefined;
    var members_count: usize = 0;
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var name_tok = try parserExpect(self, TokenKind.identifier);
        var mpt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, mpt));
        members_buf[members_count] = name_id;
        members_count += 1;
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (members_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, members_buf[0..members_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.enum_decl, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        0, 0, 0, payload);
}

fn parserParseUnionType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var is_tagged: u8 = 0;
    if (parserPeek(self).kind == TokenKind.lparen) {
        _ = parserAdvance(self);
        _ = try parserExpect(self, TokenKind.kw_enum);
        _ = try parserExpect(self, TokenKind.rparen);
        is_tagged = 1;
    }
    _ = try parserExpect(self, TokenKind.lbrace);
    var fields_buf: [64]u32 = undefined;
    var fields_count: usize = 0;
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var name_tok = try parserExpect(self, TokenKind.identifier);
        var upt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, upt));
        var field_node: u32 = 0;
        if (parserPeek(self).kind == TokenKind.colon) {
            _ = parserAdvance(self);
            var field_type = try parserParseType(self);
            field_node = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
                name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
                field_type, 0, 0, name_id);
        }
        fields_buf[fields_count] = field_node;
        fields_count += 1;
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (fields_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, fields_buf[0..fields_count]);
    }
    var kind: AstKind = AstKind.union_decl;
    if (is_tagged != 0) {
        // tagged_union_type for union(enum) — keep as union_decl with flags
    }
    return ast_mod.astStoreAddNode(self.store, kind, is_tagged,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        0, 0, 0, payload);
}

fn parserParseTypeName(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var pt = ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    var node = ast_mod.astStoreAddIdentifier(self.store, AstKind.ident_expr, name_id, tok.span_start,
        tok.span_start + @intCast(u32, tok.span_len));
    while (parserPeek(self).kind == TokenKind.dot) {
        _ = parserAdvance(self);
        var field_tok = try parserExpect(self, TokenKind.identifier);
        var fpt = ParseToken{ .kind = field_tok.kind, .span_start = field_tok.span_start, .span_len = field_tok.span_len };
        var field_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, fpt));
        node = ast_mod.astStoreAddNode(self.store, AstKind.field_access, 0,
            tok.span_start, field_tok.span_start + @intCast(u32, field_tok.span_len),
            node, 0, 0, field_id);
    }
    return node;
}

pub fn parserParseStatement(self: *Parser) ParserError!u32 {
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.kw_const) return parserParseVarDecl(self, false, false, false);
    if (tok.kind == TokenKind.kw_var) return parserParseVarDecl(self, true, false, false);
    if (tok.kind == TokenKind.kw_pub) return parserParsePubDecl(self);
    if (tok.kind == TokenKind.kw_extern) return parserParseExternDecl(self, false);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnDecl(self, false, false, false);
    if (tok.kind == TokenKind.kw_if) return parserParseIfStmt(self);
    if (tok.kind == TokenKind.kw_while) return parserParseWhileStmt(self);
    if (tok.kind == TokenKind.kw_for) return parserParseForStmt(self);
    if (tok.kind == TokenKind.kw_switch) return parserParseSwitchStmt(self);
    if (tok.kind == TokenKind.kw_return) return parserParseReturnStmt(self);
    if (tok.kind == TokenKind.kw_break) return parserParseBreakStmt(self);
    if (tok.kind == TokenKind.kw_continue) return parserParseContinueStmt(self);
    if (tok.kind == TokenKind.kw_defer) return parserParseDeferStmt(self, AstKind.defer_stmt);
    if (tok.kind == TokenKind.kw_errdefer) return parserParseErrdeferStmt(self);
    if (tok.kind == TokenKind.kw_test) return parserParseTestDecl(self);
    if (tok.kind == TokenKind.kw_struct) return parserParseContainerDecl(self, AstKind.struct_decl);
    if (tok.kind == TokenKind.kw_enum) return parserParseContainerDecl(self, AstKind.enum_decl);
    if (tok.kind == TokenKind.kw_union) return parserParseContainerDecl(self, AstKind.union_decl);
    if (tok.kind == TokenKind.lbrace) return parserParseBlock(self);
    if (tok.kind == TokenKind.semicolon) {
        _ = parserAdvance(self);
        return parserParseStatement(self);
    }
    if (tok.kind == TokenKind.identifier) {
        if (parserPeekN(self, 1).kind == TokenKind.colon) return parserParseLabeledStmt(self);
        return parserParseExprStmt(self);
    }
    return parserParseExprStmt(self);
}

pub fn parserEmitErrorNode(self: *Parser, tok: Token, msg: []const u8) u32 {
    parserAddError(self, tok, msg);
    return ast_mod.astStoreAddNode(self.store, AstKind.err, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        0, 0, 0, 0);
}

pub fn parserParseModuleRoot(self: *Parser) ParserError!u32 {
    var decl_buf: [64]u32 = undefined;
    var decl_count: usize = 0;

    while (parserPeek(self).kind != TokenKind.eof) {
        var decl = parserParseStatement(self) catch {
            var tok = parserPeek(self);
            var err_msg: []const u8 = "unexpected token";
            var err = parserEmitErrorNode(self, tok, err_msg);
            parserSynchronize(self);
            decl_buf[decl_count] = err;
            decl_count += 1;
            while (parserPeek(self).kind == TokenKind.semicolon) _ = parserAdvance(self);
            continue;
        };
        decl_buf[decl_count] = decl;
        decl_count += 1;
    }

    var payload: u32 = 0;
    if (decl_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, decl_buf[0..decl_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.module_root, 0, 0, 0, 0, 0, 0, payload);
}

fn parserParseExprStmt(self: *Parser) ParserError!u32 {
    var result = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.semicolon);
    return result;
}

fn parserParseLabeledStmt(self: *Parser) ParserError!u32 {
    var label_tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.colon);
    var inner = try parserParseStatement(self);
    var end = inner; _ = end;
    return ast_mod.astStoreAddNode(self.store, AstKind.labeled_stmt, 0,
        label_tok.span_start, label_tok.span_start + @intCast(u32, label_tok.span_len),
        inner, 0, 0, 0);
}

fn parserParseLabeledBlockExpr(self: *Parser) ParserError!u32 {
    var label_tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.colon);
    var body = try parserParseBlock(self);
    var end_pos: u32 = label_tok.span_start;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.labeled_stmt, 0,
        label_tok.span_start, end_pos, body, 0, 0, 0);
}

fn parserParseVarDecl(self: *Parser, is_mutable: bool, is_pub: bool, is_extern: bool) ParserError!u32 {
    var kw = parserAdvance(self);
    var name_tok = try parserExpect(self, TokenKind.identifier);
    var flags: u8 = 0;
    if (is_mutable) flags = flags | @intCast(u8, 0x01);
    if (is_pub) flags = flags | @intCast(u8, 0x02);
    if (is_extern) flags = flags | @intCast(u8, 0x04);
    var type_node: u32 = 0;
    if (parserPeek(self).kind == TokenKind.colon) {
        _ = parserAdvance(self);
        type_node = try parserParseType(self);
    }
    var init_node: u32 = 0;
    if (parserPeek(self).kind == TokenKind.eq) {
        _ = parserAdvance(self);
        init_node = try parserParseExprPrec(self, Prec.none);
    }
    var semi = try parserExpect(self, TokenKind.semicolon);
    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self,
        ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len }));
    var end_pos: u32 = semi.span_start + @intCast(u32, semi.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.var_decl, flags,
        kw.span_start, end_pos, type_node, init_node, 0, name_id);
}
fn parserParsePubDecl(self: *Parser) ParserError!u32 {
    _ = parserAdvance(self);
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnDecl(self, true, false, false);
    if (tok.kind == TokenKind.kw_const) return parserParseVarDecl(self, false, true, false);
    if (tok.kind == TokenKind.kw_var) return parserParseVarDecl(self, true, true, false);
    if (tok.kind == TokenKind.kw_test) return parserParseTestDecl(self);
    if (tok.kind == TokenKind.kw_extern) return parserParseExternDecl(self, true);
    var p_msg: []const u8 = "expected fn/const/var after pub";
    parserAddError(self, tok, p_msg);
    return error.UnexpectedToken;
}
fn parserParseExternDecl(self: *Parser, is_pub: bool) ParserError!u32 {
    _ = parserAdvance(self);
    if (parserPeek(self).kind == TokenKind.string_literal) {
        _ = parserAdvance(self);
    }
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnDecl(self, is_pub, true, false);
    if (tok.kind == TokenKind.kw_const) return parserParseVarDecl(self, false, is_pub, true);
    if (tok.kind == TokenKind.kw_var) return parserParseVarDecl(self, true, is_pub, true);
    var e_msg: []const u8 = "expected fn/const/var after extern";
    parserAddError(self, tok, e_msg);
    return error.UnexpectedToken;
}
fn parserParseFnDecl(self: *Parser, is_pub: bool, is_extern: bool, is_test: bool) ParserError!u32 {
    var kw = parserAdvance(self);
    var flags: u8 = 0;
    if (is_pub) flags = flags | @intCast(u8, 0x02);
    if (is_extern) flags = flags | @intCast(u8, 0x04);
    if (is_test) flags = flags | @intCast(u8, 0x20);

    var name_tok = try parserExpect(self, TokenKind.identifier);
    _ = try parserExpect(self, TokenKind.lparen);

    self.child_buf_len = 0;
    while (parserPeek(self).kind != TokenKind.rparen and parserPeek(self).kind != TokenKind.eof) {
        var param_tok = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.colon);
        var param_type = try parserParseType(self);
        var param_name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self,
            ParseToken{ .kind = param_tok.kind, .span_start = param_tok.span_start, .span_len = param_tok.span_len }));
        var param_node = ast_mod.astStoreAddNode(self.store, AstKind.param_decl, 0,
            param_tok.span_start, self.last_end, param_type, 0, 0, param_name_id);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, param_node);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    _ = try parserExpect(self, TokenKind.rparen);

    var ret_type_node: u32 = 0;
    if (parserPeek(self).kind == TokenKind.colon) {
        _ = parserAdvance(self);
        ret_type_node = try parserParseType(self);
    } else if (parserPeek(self).kind != TokenKind.semicolon and parserPeek(self).kind != TokenKind.lbrace) {
        ret_type_node = try parserParseType(self);
    }

    var body_node: u32 = 0;
    var end_pos: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.semicolon) {
        var semi = parserAdvance(self);
        end_pos = semi.span_start + @intCast(u32, semi.span_len);
    } else {
        body_node = try parserParseBlock(self);
        end_pos = self.last_end;
    }

    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self,
        ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len }));
    var param_payload: u32 = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    var proto: FnProto = FnProto{ .name_id = name_id, .params_start = @intCast(u16, param_payload >> 16), .params_count = @intCast(u16, self.child_buf_len), .return_type_node = ret_type_node };
    var proto_idx: u32 = ast_mod.astStoreAddFnProto(self.store, proto);
    self.child_buf_len = 0;
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_decl, flags, kw.span_start, end_pos, body_node, 0, 0, proto_idx);
}

fn parserParseIfStmt(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var cond = try parserParseExprPrec(self, Prec.none);
    _ = try parserExpect(self, TokenKind.rparen);

    var capture_node: u32 = 0;
    if (parserPeek(self).kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var name_tok = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.pipe);
        var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
        capture_node = ast_mod.astStoreAddNode(self.store, AstKind.if_capture, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            0, 0, 0, name_id);
    }

    var then_body: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.lbrace) {
        then_body = try parserParseBlock(self);
    } else {
        then_body = try parserParseExprPrec(self, Prec.assignment);
    }

    var else_node: u32 = 0;
    if (parserPeek(self).kind == TokenKind.kw_else) {
        _ = parserAdvance(self);
        if (parserPeek(self).kind == TokenKind.kw_if) {
            else_node = try parserParseIfStmt(self);
        } else if (parserPeek(self).kind == TokenKind.lbrace) {
            else_node = try parserParseBlock(self);
        } else {
            else_node = try parserParseExprPrec(self, Prec.assignment);
        }
    }
    var end_pos: u32 = kw.span_start;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.if_stmt, 0,
        kw.span_start, end_pos, cond, then_body, else_node, capture_node);
}

fn parserParseWhileStmt(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var cond = try parserParseExprPrec(self, Prec.none);
    _ = try parserExpect(self, TokenKind.rparen);

    var capture_name: u32 = 0;
    if (parserPeek(self).kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var cap_tok: ParseToken = undefined;
        if (parserPeek(self).kind == TokenKind.underscore) {
            cap_tok = try parserExpect(self, TokenKind.underscore);
        } else {
            cap_tok = try parserExpect(self, TokenKind.identifier);
        }
        capture_name = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, cap_tok));
        _ = try parserExpect(self, TokenKind.pipe);
    }

    var continue_expr: u32 = 0;
    if (parserPeek(self).kind == TokenKind.colon) {
        _ = parserAdvance(self);
        _ = try parserExpect(self, TokenKind.lparen);
        continue_expr = try parserParseExprPrec(self, Prec.none);
        _ = try parserExpect(self, TokenKind.rparen);
    }

    var body = try parserParseBlock(self);
    var end_pos: u32 = undefined;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    } else end_pos = kw.span_start;
    return ast_mod.astStoreAddNode(self.store, AstKind.while_stmt, 0,
        kw.span_start, end_pos, cond, body, continue_expr, capture_name);
}

fn parserParseForStmt(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var pattern = try parserParseExprPrec(self, Prec.none);
    if (parserPeek(self).kind == TokenKind.dot_dot) {
        _ = parserAdvance(self);
        var end_node = try parserParseExprPrec(self, Prec.none);
        pattern = ast_mod.astStoreAddNode(self.store, AstKind.range_exclusive, 0,
            0, 0, pattern, end_node, 0, 0);
    }
    _ = try parserExpect(self, TokenKind.rparen);

    var capture_name: u32 = 0;
    var index_name: u32 = 0;
    if (parserPeek(self).kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var cap_tok: ParseToken = undefined;
        if (parserPeek(self).kind == TokenKind.underscore) {
            cap_tok = try parserExpect(self, TokenKind.underscore);
        } else {
            cap_tok = try parserExpect(self, TokenKind.identifier);
        }
        capture_name = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, cap_tok));
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
            var idx_tok = try parserExpect(self, TokenKind.identifier);
            index_name = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self,
                ParseToken{ .kind = idx_tok.kind, .span_start = idx_tok.span_start, .span_len = idx_tok.span_len }));
        }
        _ = try parserExpect(self, TokenKind.pipe);
    }

    var body = try parserParseBlock(self);
    var end_pos: u32 = undefined;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    } else end_pos = kw.span_start;
    return ast_mod.astStoreAddNode(self.store, AstKind.for_stmt, 0,
        kw.span_start, end_pos, pattern, body, index_name, capture_name);
}
fn parserParseSwitchStmt(self: *Parser) ParserError!u32 {
    var inner = try parserParseSwitchExpr(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.expr_stmt, 0, 0, 0, inner, 0, 0, 0);
}
fn parserParseReturnExpr(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    var expr: u32 = 0;
    if (parserPeek(self).kind != TokenKind.semicolon) {
        expr = try parserParseExprPrec(self, Prec.none);
    }
    var end_pos: u32 = kw.span_start + @intCast(u32, kw.span_len);
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.return_stmt, 0,
        kw.span_start, end_pos, expr, 0, 0, 0);
}
fn parserParseBreakExpr(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    var label_id: u32 = 0;
    if (parserPeek(self).kind == TokenKind.colon) {
        _ = parserAdvance(self);
        var label_tok = try parserExpect(self, TokenKind.identifier);
        var pt = ParseToken{ .kind = label_tok.kind, .span_start = label_tok.span_start, .span_len = label_tok.span_len };
        label_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    }
    var end_pos: u32 = kw.span_start + @intCast(u32, kw.span_len);
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.break_stmt, 0,
        kw.span_start, end_pos, 0, 0, 0, label_id);
}
fn parserParseContinueExpr(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    var label_id: u32 = 0;
    if (parserPeek(self).kind == TokenKind.colon) {
        _ = parserAdvance(self);
        var label_tok = try parserExpect(self, TokenKind.identifier);
        var pt = ParseToken{ .kind = label_tok.kind, .span_start = label_tok.span_start, .span_len = label_tok.span_len };
        label_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    }
    var end_pos: u32 = kw.span_start + @intCast(u32, kw.span_len);
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.continue_stmt, 0,
        kw.span_start, end_pos, 0, 0, 0, label_id);
}
fn parserParseReturnStmt(self: *Parser) ParserError!u32 {
    var node = try parserParseReturnExpr(self);
    _ = try parserExpect(self, TokenKind.semicolon);
    return node;
}
fn parserParseBreakStmt(self: *Parser) ParserError!u32 {
    var node = try parserParseBreakExpr(self);
    _ = try parserExpect(self, TokenKind.semicolon);
    return node;
}
fn parserParseContinueStmt(self: *Parser) ParserError!u32 {
    var node = try parserParseContinueExpr(self);
    _ = try parserExpect(self, TokenKind.semicolon);
    return node;
}
fn parserParseDeferStmt(self: *Parser, kind: AstKind) ParserError!u32 {
    var kw = parserAdvance(self);
    var body = try parserParseStatement(self);
    var end_pos: u32 = kw.span_start;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    }
    return ast_mod.astStoreAddNode(self.store, kind, 0,
        kw.span_start, end_pos, body, 0, 0, 0);
}
fn parserParseErrdeferStmt(self: *Parser) ParserError!u32 {
    return parserParseDeferStmt(self, AstKind.errdefer_stmt);
}
fn parserParseTestDecl(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var name_id: u32 = 0;
    if (parserPeek(self).kind == TokenKind.string_literal) {
        var name_tok = parserAdvance(self);
        var npt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, npt));
    }
    var body = try parserParseBlock(self);
    var end_pos: u32 = undefined;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    } else end_pos = tok.span_start;
    return ast_mod.astStoreAddNode(self.store, AstKind.test_decl, 0,
        tok.span_start, end_pos, body, 0, 0, name_id);
}
fn parserParseContainerDecl(self: *Parser, kind: AstKind) ParserError!u32 {
    var tok = parserAdvance(self);
    var name_id: u32 = 0;
    var is_tagged: u8 = 0;
    if (kind == AstKind.union_decl and parserPeek(self).kind == TokenKind.lparen) {
        _ = parserAdvance(self);
        _ = try parserExpect(self, TokenKind.kw_enum);
        _ = try parserExpect(self, TokenKind.rparen);
        is_tagged = 1;
    }
    if (parserPeek(self).kind == TokenKind.identifier) {
        var name_tok = parserAdvance(self);
        var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    }
    _ = try parserExpect(self, TokenKind.lbrace);
    var fields_buf: [64]u32 = undefined;
    var fields_count: usize = 0;
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var ftok = try parserExpect(self, TokenKind.identifier);
        var fpt = ParseToken{ .kind = ftok.kind, .span_start = ftok.span_start, .span_len = ftok.span_len };
        var fid = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, fpt));
        if (kind == AstKind.enum_decl) {
            fields_buf[fields_count] = fid;
            fields_count += 1;
        } else {
            _ = try parserExpect(self, TokenKind.colon);
            var ftype = try parserParseType(self);
            var fnode = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
                ftok.span_start, ftok.span_start + @intCast(u32, ftok.span_len),
                ftype, 0, 0, fid);
            fields_buf[fields_count] = fnode;
            fields_count += 1;
        }
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u32 = 0;
    if (fields_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, fields_buf[0..fields_count]);
    }
    var end_pos: u32 = rbrace.span_start + @intCast(u32, rbrace.span_len);
    return ast_mod.astStoreAddNode(self.store, kind, is_tagged,
        tok.span_start, end_pos, name_id, 0, 0, payload);
}
fn parserParseBlock(self: *Parser) ParserError!u32 {
    var lbrace = try parserExpect(self, TokenKind.lbrace);
    self.child_buf_len = 0;
    while (parserPeek(self).kind != TokenKind.rbrace and parserPeek(self).kind != TokenKind.eof) {
        var stmt = try parserParseStatement(self);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, stmt);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
    self.child_buf_len = 0;
    return ast_mod.astStoreAddNode(self.store, AstKind.block, 0, lbrace.span_start, rbrace.span_start + @intCast(u32, rbrace.span_len), 0, 0, 0, payload);
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
