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
const pal = @import("pal.zig");
const itoa_mod = @import("util/itoa.zig");
const format_mod = @import("util/format.zig");
const mr_mod = @import("module_registry.zig");
const ModuleRegistry = mr_mod.ModuleRegistry;

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
    decl_buf_items: [*]u32,
    decl_buf_len: usize,
    decl_buf_capacity: usize,
    builtin_import_id: u32,
    catch_capture: u32,
    expr_depth: u32,
    module_reg: ?*ModuleRegistry,
    import_scratch: ?*Sand,
    current_module_id: u32,
    file_id: u32,
};

pub fn parserInit(tokens: []const Token, source: []const u8, store: *AstStore, interner: *StringInterner, diag: *DiagnosticCollector, alloc: *Sand) Parser {
    var t_ptr = @ptrCast([*]Token, tokens.ptr);
    var import_s: []const u8 = "@import";
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
        .decl_buf_items = undefined,
        .decl_buf_len = @intCast(usize, 0),
        .decl_buf_capacity = @intCast(usize, 0),
        .catch_capture = @intCast(u32, 0),
        .expr_depth = @intCast(u32, 0),
        .builtin_import_id = import_id,
        .module_reg = null,
        .import_scratch = null,
        .current_module_id = @intCast(u32, 0),
        .file_id = @intCast(u32, 0),
    };
}

pub fn parserSetModuleContext(self: *Parser, reg: *ModuleRegistry, mod_id: u32) void {
    self.module_reg = reg;
    self.current_module_id = mod_id;
    self.file_id = reg.modules.items[mod_id].source_file_id;
}

pub fn parserSetImportScratch(self: *Parser, scratch: *Sand) void {
    self.import_scratch = scratch;
}

pub fn parserTokenText(self: *Parser, tok: ParseToken) []const u8 {
    var start = @intCast(usize, tok.span_start);
    var end: usize = start + @intCast(usize, tok.span_len);
    return self.source_ptr[start..end];
}

pub fn parserPeek(self: *Parser) Token {
    if (self.pos >= self.tokens_len) return self.tokens_ptr[self.tokens_len - 1];
    return self.tokens_ptr[self.pos];
}

pub fn parserPeekN(self: *Parser, n: usize) Token {
    var idx: usize = self.pos + n;
    if (idx >= self.tokens_len) return self.tokens_ptr[self.tokens_len - 1];
    return self.tokens_ptr[idx];
}

pub fn parserAdvance(self: *Parser) Token {
    var tok = parserPeek(self);
    if (self.pos < self.tokens_len) self.pos += 1;
    self.last_end = tok.span_start + @intCast(u32, tok.span_len);
    return tok;
}

fn tokenKindLabel(kind: TokenKind) []const u8 {
    if (kind == TokenKind.semicolon) { var s: []const u8 = "';'"; return s; }
    if (kind == TokenKind.lparen) { var s: []const u8 = "'('"; return s; }
    if (kind == TokenKind.rparen) { var s: []const u8 = "')'"; return s; }
    if (kind == TokenKind.lbrace) { var s: []const u8 = "'{'"; return s; }
    if (kind == TokenKind.rbrace) { var s: []const u8 = "'}'"; return s; }
    if (kind == TokenKind.lbracket) { var s: []const u8 = "'['"; return s; }
    if (kind == TokenKind.rbracket) { var s: []const u8 = "']'"; return s; }
    if (kind == TokenKind.comma) { var s: []const u8 = "','"; return s; }
    if (kind == TokenKind.dot) { var s: []const u8 = "'.'"; return s; }
    if (kind == TokenKind.colon) { var s: []const u8 = "':'"; return s; }
    if (kind == TokenKind.pipe) { var s: []const u8 = "'|'"; return s; }
    if (kind == TokenKind.identifier) { var s: []const u8 = "identifier"; return s; }
    if (kind == TokenKind.string_literal) { var s: []const u8 = "string literal"; return s; }
    if (kind == TokenKind.integer_literal) { var s: []const u8 = "integer literal"; return s; }
    if (kind == TokenKind.kw_fn) { var s: []const u8 = "'fn'"; return s; }
    if (kind == TokenKind.kw_while) { var s: []const u8 = "'while'"; return s; }
    if (kind == TokenKind.kw_if) { var s: []const u8 = "'if'"; return s; }
    if (kind == TokenKind.kw_else) { var s: []const u8 = "'else'"; return s; }
    if (kind == TokenKind.kw_return) { var s: []const u8 = "'return'"; return s; }
    if (kind == TokenKind.kw_const) { var s: []const u8 = "'const'"; return s; }
    if (kind == TokenKind.kw_var) { var s: []const u8 = "'var'"; return s; }
    if (kind == TokenKind.kw_pub) { var s: []const u8 = "'pub'"; return s; }
    if (kind == TokenKind.kw_extern) { var s: []const u8 = "'extern'"; return s; }
    var fallback: []const u8 = "token"; return fallback;
}

pub fn parserExpect(self: *Parser, kind: TokenKind) ParserError!ParseToken {
    var tok = parserPeek(self);
    if (tok.kind != kind) {
        var exp_s: []const u8 = "expected ";
        var exp_lab = tokenKindLabel(kind);
        var fnd_s: []const u8 = " but found ";
        var fnd_lab = tokenKindLabel(tok.kind);
        var parts: [4][]const u8 = [4][]const u8{exp_s, exp_lab, fnd_s, fnd_lab};
        var msg = diag_mod.diagnosticBuilderMakeMsg(self.diag.interner, &parts[0], @intCast(u32, 4));
        parserAddError(self, tok, msg);
        return error.UnexpectedToken;
    }
    // consume via advanceTok and return ParseToken
    if (self.pos < self.tokens_len) self.pos += 1;
    return ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
}

pub fn parserAddError(self: *Parser, tok: Token, msg: []const u8) void {
    diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 2000),
        self.file_id, tok.span_start, tok.span_start + @intCast(u32, tok.span_len), msg);
}

pub fn parserSynchronize(self: *Parser) void {
    while (self.pos < self.tokens_len) {
        var k = self.tokens_ptr[self.pos].kind;
        if (k == TokenKind.semicolon or k == TokenKind.rbrace or k == TokenKind.kw_fn or
            k == TokenKind.kw_const or k == TokenKind.kw_var or k == TokenKind.kw_pub or
            k == TokenKind.kw_test) {
            self.pos += 1;
            return;
        }
        if (k == TokenKind.eof) return;
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
        var catch_handled: u8 = 0;
        if (tok.kind == TokenKind.kw_catch) {
            var cap: u32 = @intCast(u32, 0);
            rhs = try parserParseCatchRHS(self, next_min, &cap);
            var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
            lhs = ast_mod.astStoreAddNode(self.store, AstKind.catch_expr, 0, tok.span_start, end, lhs, rhs, cap, 0);
            catch_handled = 1;
        } else if (tok.kind == TokenKind.kw_orelse) {
            rhs = try parserParseOrelseRHS(self, next_min);
        } else {
            rhs = try parserParseExprPrec(self, next_min);
        }

        if (catch_handled == 0) {
            lhs = try parserAddBinary(self, tok, lhs, rhs);
        }
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
        TokenKind.eq => { kind = AstKind.plain_assign; found = 1; },
        TokenKind.plus_eq => { kind = AstKind.add_assign; found = 1; },
        TokenKind.minus_eq => { kind = AstKind.sub_assign; found = 1; },
        TokenKind.star_eq => { kind = AstKind.mul_assign; found = 1; },
        TokenKind.plus_pct => { kind = AstKind.wrap_add; found = 1; },
        TokenKind.minus_pct => { kind = AstKind.wrap_sub; found = 1; },
        TokenKind.star_pct => { kind = AstKind.wrap_mul; found = 1; },
        TokenKind.plus_pct_eq => { kind = AstKind.wrap_add_assign; found = 1; },
        TokenKind.minus_pct_eq => { kind = AstKind.wrap_sub_assign; found = 1; },
        TokenKind.star_pct_eq => { kind = AstKind.wrap_mul_assign; found = 1; },
        TokenKind.plus_pipe => { kind = AstKind.sat_add; found = 1; },
        TokenKind.minus_pipe => { kind = AstKind.sat_sub; found = 1; },
        TokenKind.star_pipe => { kind = AstKind.sat_mul; found = 1; },
        TokenKind.shl_pipe => { kind = AstKind.sat_shl; found = 1; },
        TokenKind.plus_pipe_eq => { kind = AstKind.sat_add_assign; found = 1; },
        TokenKind.minus_pipe_eq => { kind = AstKind.sat_sub_assign; found = 1; },
        TokenKind.star_pipe_eq => { kind = AstKind.sat_mul_assign; found = 1; },
        TokenKind.shl_pipe_eq => { kind = AstKind.sat_shl_assign; found = 1; },
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
        var add_msg: []const u8 = "invalid token in expression";
        parserAddError(self, tok, add_msg);
        return error.UnexpectedToken;
    }
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    if (kind == AstKind.catch_expr) {
        return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start, end, lhs, rhs, self.catch_capture, 0);
    }
    var bok: []const u8 = "BOP:tk"; pal.markerWrite(bok);
    var bokb: [10]u8 = undefined; var bokl = itoa_mod.itoa(@enumToInt(tok.kind), bokb[0..]); var boks: usize = @intCast(usize, 9) - @intCast(usize, bokl); pal.markerWrite(bokb[boks..@intCast(usize, 9)]);
    var bokk: []const u8 = "ak"; pal.markerWrite(bokk);
    var bokkb: [10]u8 = undefined; var bokkl = itoa_mod.itoa(@enumToInt(kind), bokkb[0..]); var bokks: usize = @intCast(usize, 9) - @intCast(usize, bokkl); pal.markerWrite(bokkb[bokks..@intCast(usize, 9)]);
    var boknl: []const u8 = " "; pal.markerWrite(boknl);
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
    if (tok.kind == TokenKind.kw_bool) return parserParseIdentExpr(self);
    if (tok.kind == TokenKind.kw_c_char) return parserParseIdentExpr(self);
    if (tok.kind == TokenKind.kw_void) return parserParseIdentExpr(self);
    if (tok.kind == TokenKind.builtin_identifier) return parserParseBuiltinCall(self);
    if (tok.kind == TokenKind.c_include_builtin) return parserParseCInclude(self);
    if (tok.kind == TokenKind.kw_error) return parserParseErrorLiteral(self);
    if (tok.kind == TokenKind.minus) return parserParsePrefixUnary(self, AstKind.negate);
    if (tok.kind == TokenKind.minus_pct) return parserParsePrefixUnary(self, AstKind.wrap_negate);
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
    var primary_msg: []const u8 = "expected expression";
    parserAddError(self, tok, primary_msg);
    return error.UnexpectedToken;
}

pub fn parserParsePostfixChain(self: *Parser, base: u32) ParserError!u32 {
    var node = base;
    while (true) {
        var tok = parserPeek(self);
        if (tok.kind == TokenKind.dot_star) {
            _ = parserAdvance(self);
            node = ast_mod.astStoreAddNode(self.store, AstKind.deref, 0,
                tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
                node, 0, 0, 0);
        } else if (tok.kind == TokenKind.dot) {
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
    if (@intCast(u32, @enumToInt(tok.kind)) == @intCast(u32, @enumToInt(TokenKind.star))) {
        _ = parserAdvance(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.deref, 0,
            tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
            base, 0, 0, 0);
    }
    var name_id = tok.value.string_id;
    _ = parserAdvance(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.field_access, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        base, 0, 0, name_id);
}

fn parserParseIndexOrSlice(self: *Parser, base: u32) ParserError!u32 {
    _ = parserAdvance(self);
    var first = try parserParseExprPrec(self, Prec.none);
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.dot_dot) {
        _ = parserAdvance(self);
        var last: u32 = 0;
        if (parserPeek(self).kind == TokenKind.rbracket) {
            // open-ended range: grid[0..]
        } else {
            last = try parserParseExprPrec(self, Prec.none);
        }
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
    var end: u32 = rparen.span_start + @intCast(u32, rparen.span_len);
        return ast_mod.astStoreAddNode(self.store, AstKind.fn_call, 0, lparen.span_start, end, base, 0, 0, 0);
    }
    var saved_fncall: usize = self.child_buf_len;
    while (true) {
        var arg = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
        if (parserPeek(self).kind == TokenKind.rparen) break;
        _ = try parserExpect(self, TokenKind.comma);
        if (parserPeek(self).kind == TokenKind.rparen) break;
    }
    var rparen = try parserExpect(self, TokenKind.rparen);
    var end: u32 = rparen.span_start + @intCast(u32, rparen.span_len);
    var payload: u64 = 0;
    if (self.child_buf_len > saved_fncall) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[saved_fncall..self.child_buf_len]);
    }
    self.child_buf_len = saved_fncall;
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_call, 0, lparen.span_start, end, base, 0, 0, payload);
}

fn parserParseCatchRHS(self: *Parser, next_min: Prec, capture_out: *u32) ParserError!u32 {
    capture_out.* = @intCast(u32, 0);
    var ptok = parserPeek(self);
    if (ptok.kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var name_raw2 = parserPeek(self);
        _ = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.pipe);
        var name_id = name_raw2.value.string_id;
        capture_out.* = ast_mod.astStoreAddNode(self.store, AstKind.payload_capture, 0,
            name_raw2.span_start, name_raw2.span_start + @intCast(u32, name_raw2.span_len),
            0, 0, 0, name_id);
    }
    var result: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.lbrace) {
        result = try parserParseBlock(self);
    } else {
        result = try parserParseExprPrec(self, next_min);
    }
    return result;
}

fn parserParseOrelseRHS(self: *Parser, next_min: Prec) ParserError!u32 {
    if (parserPeek(self).kind == TokenKind.lbrace) {
        return parserParseBlock(self);
    }
    return parserParseExprPrec(self, next_min);
}

fn parserParseFieldInitListNamed(self: *Parser) ParserError!u64 {
    var saved_child_len = self.child_buf_len;
    while (parserPeek(self).kind == TokenKind.dot) {
        _ = parserAdvance(self);
        var name_raw3 = parserPeek(self);
        _ = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.eq);
        var val = try parserParseExprPrec(self, Prec.none);
        var name_id = name_raw3.value.string_id;
        var field = ast_mod.astStoreAddNode(self.store, AstKind.field_init, 0,
            name_raw3.span_start, name_raw3.span_start + @intCast(u32, name_raw3.span_len),
            val, 0, 0, name_id);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len,
            &self.child_buf_capacity, self.allocator, field);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (self.child_buf_len > saved_child_len) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[saved_child_len..self.child_buf_len]);
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
        if (capacity.* > 0) {
            var grown = alloc_mod.sandTryReallocInPlace(arena,
                @ptrCast([*]u8, items.*),
                capacity.* * @intCast(usize, 4),
                new_cap * @intCast(usize, 4),
                @intCast(usize, 4));
            if (grown != null) {
                capacity.* = new_cap;
                items.*[len.*] = value;
                len.* += 1;
                return;
            }
        }
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

fn parserPushU32(self: *Parser, buf: *[*]u32, len: *usize, cap: *usize, v: u32) void {
    u32ArrayListAppendInner(buf, len, cap, self.allocator, v);
}

fn parserParseIntLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddIntLiteral(self.store, tok.value.int_val, tok.span_start, end);
}

fn parserParseFloatLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    var dbg_buf: [64]u8 = undefined;
    var dbg = format_mod.formatF64(tok.value.float_val, dbg_buf[0..], 64);
    var ps: []const u8 = "PF:"; pal.markerWrite(ps);
    pal.markerWrite(dbg);
    var pn: []const u8 = "\n"; pal.markerWrite(pn);
    return ast_mod.astStoreAddFloatLiteral(self.store, tok.value.float_val, tok.span_start, end);
}

fn parserParseStringLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddStringLiteral(self.store, tok.value.string_id, tok.span_start, end);
}

fn parserParseCharLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddCharLiteral(self.store, tok.value.int_val, tok.span_start, end);
}

fn parserParseBoolLiteral(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var val: u8 = 0;
    if (tok.kind == TokenKind.kw_true) val = 1;
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.bool_literal, val, tok.span_start, end, 0, 0, 0, 0);
}

fn parserParseSingleToken(self: *Parser, kind: AstKind) ParserError!u32 {
    var tok = parserAdvance(self);
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start, end, 0, 0, 0, 0);
}

fn parserParseIdentExpr(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var pt = ParseToken{ .kind = tok.kind, .span_start = tok.span_start, .span_len = tok.span_len };
    var id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddIdentifier(self.store, AstKind.ident_expr, id, tok.span_start, end);
}

fn parserParsePrefixUnary(self: *Parser, kind: AstKind) ParserError!u32 {
    var tok = parserAdvance(self);
    var operand = try parserParseExprPrec(self, Prec.prefix);
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start,
        end, operand, 0, 0, 0);
}

fn parserParseGroupedExpr(self: *Parser) ParserError!u32 {
    var lparen = parserAdvance(self);
    var inner = try parserParseExprPrec(self, Prec.assignment);
    var rparen = try parserExpect(self, TokenKind.rparen);
    return ast_mod.astStoreAddNode(self.store, AstKind.paren_expr, 0,
        lparen.span_start, rparen.span_start + @intCast(u32, rparen.span_len),
        inner, 0, 0, 0);
}

fn parserParseBuiltinCall(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    if (tok.value.string_id == self.builtin_import_id) {
        self.child_buf_len = 0;
        return parserParseImportExpr(self, tok);
    }
    var id = tok.value.string_id;
    var end: u32 = tok.span_start + @intCast(u32, tok.span_len);
    var lparen = parserPeek(self);
    if (lparen.kind != TokenKind.lparen) {
        var exp_s: []const u8 = "expected '(' after builtin name";
        parserAddError(self, lparen, exp_s);
        return error.UnexpectedToken;
    }
    _ = parserAdvance(self);
     var saved_builtin: usize = self.child_buf_len;
     while (true) {
         if (parserPeek(self).kind == TokenKind.rparen) break;
         var tok = parserPeek(self);
         var is_type: u8 = @intCast(u8, 0);
         if (tok.kind == TokenKind.star) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.lbracket) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.question_mark) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.bang) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.kw_fn) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.kw_struct) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.kw_enum) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.kw_union) { is_type = @intCast(u8, 1); }
         if (tok.kind == TokenKind.kw_error) { is_type = @intCast(u8, 1); }
          if (tok.kind == TokenKind.kw_anytype) { is_type = @intCast(u8, 1); }
          if (is_type != @intCast(u8, 0)) {
             var arg = try parserParseType(self);
             u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
         } else {
             var arg = try parserParseExprPrec(self, Prec.none);
             u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, arg);
         }
         if (parserPeek(self).kind == TokenKind.rparen) break;
         _ = try parserExpect(self, TokenKind.comma);
     }
    var rparen = parserAdvance(self);
    end = rparen.span_start + @intCast(u32, rparen.span_len);
    var payload: u64 = 0;
    if (self.child_buf_len > saved_builtin) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[saved_builtin..self.child_buf_len]);
    }
    self.child_buf_len = saved_builtin;
    return ast_mod.astStoreAddNode(self.store, AstKind.builtin_call, 0, tok.span_start, end, id, 0, 0, payload);
}

fn parserParseImportExpr(self: *Parser, bi_tok: Token) ParserError!u32 {
    var lparen = parserPeek(self);
    if (lparen.kind != TokenKind.lparen) {
        var exp_s: []const u8 = "expected '(' after @import";
        parserAddError(self, lparen, exp_s);
        return error.UnexpectedToken;
    }
    _ = parserAdvance(self);
    var path_tok = parserPeek(self);
    if (path_tok.kind != TokenKind.string_literal) {
        var exp_s: []const u8 = "expected string literal for @import path";
        parserAddError(self, path_tok, exp_s);
        return error.UnexpectedToken;
    }
    var path_id = path_tok.value.string_id;
    _ = parserAdvance(self);
    var rparen = parserPeek(self);
    if (rparen.kind != TokenKind.rparen) {
        var exp_s: []const u8 = "expected ')' after @import path";
        parserAddError(self, rparen, exp_s);
        return error.UnexpectedToken;
    }
    var end_pos: u32 = rparen.span_start + @intCast(u32, rparen.span_len);
    _ = parserAdvance(self);
    if (self.module_reg) |reg| {
        if (self.import_scratch) |is| {
            alloc_mod.sandReset(is);
            var resolved = mr_mod.moduleRegistryResolveImport(reg, path_id, self.current_module_id, is);
            _ = resolved;
        }
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.import_expr, 0,
        bi_tok.span_start, end_pos, 0, 0, 0, path_id);
}

fn parserParseCInclude(self: *Parser) ParserError!u32 {
    var bi_tok = parserAdvance(self);
    var lparen = parserPeek(self);
    if (lparen.kind != TokenKind.lparen) {
        var exp_s: []const u8 = "expected '(' after @cInclude";
        parserAddError(self, lparen, exp_s);
        return error.UnexpectedToken;
    }
    _ = parserAdvance(self);
    var name_tok = parserPeek(self);
    if (name_tok.kind != TokenKind.string_literal) {
        var exp_s: []const u8 = "expected string literal for @cInclude name";
        parserAddError(self, name_tok, exp_s);
        return error.UnexpectedToken;
    }
    var name_id = name_tok.value.string_id;
    _ = parserAdvance(self);
    var rparen = parserPeek(self);
    if (rparen.kind != TokenKind.rparen) {
        var exp_s: []const u8 = "expected ')' after @cInclude name";
        parserAddError(self, rparen, exp_s);
        return error.UnexpectedToken;
    }
    var end_pos: u32 = rparen.span_start + @intCast(u32, rparen.span_len);
    _ = parserAdvance(self);
    return ast_mod.astStoreAddNode(self.store, AstKind.c_include, 0,
        bi_tok.span_start, end_pos, 0, 0, 0, name_id);
}

fn parserParseErrorLiteral(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    if (parserPeek(self).kind == TokenKind.lbrace) {
        return parserParseErrorSetDeclBody(self, kw);
    }
    _ = try parserExpect(self, TokenKind.dot);
    var name_tok = try parserExpect(self, TokenKind.identifier);
    var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    var end: u32 = name_tok.span_start + @intCast(u32, name_tok.span_len);
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
    while (parserPeek(self).kind != TokenKind.rbrace and parserPeek(self).kind != TokenKind.eof) {
        var val = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len,
            &self.child_buf_capacity, self.allocator, val);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (self.child_buf_len > saved_child_len) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[saved_child_len..self.child_buf_len]);
    }
    self.child_buf_len = saved_child_len;
    return ast_mod.astStoreAddNode(self.store, AstKind.tuple_literal, 0,
        dot.span_start, rbrace.span_start + @intCast(u32, rbrace.span_len),
        0, 0, 0, payload);
}

fn parserParseEnumLiteral(self: *Parser) ParserError!u32 {
    var dot = parserAdvance(self);
    var name_tok = parserPeek(self);
    _ = try parserExpect(self, TokenKind.identifier);
    var end_pos: u32 = name_tok.span_start + @intCast(u32, name_tok.span_len);
    return ast_mod.astStoreAddIdentifier(self.store, AstKind.enum_literal, name_tok.value.string_id, dot.span_start, end_pos);
}

fn parserParseArrayLiteral(self: *Parser) ParserError!u32 {
    var tok = parserPeek(self);
    var type_node = try parserParseBracketType(self);
    if (parserPeek(self).kind != TokenKind.lbrace) {
        return type_node;
    }
    _ = parserAdvance(self);
    var saved_child_len = self.child_buf_len;
    while (parserPeek(self).kind != TokenKind.rbrace and parserPeek(self).kind != TokenKind.eof) {
        var val = try parserParseExprPrec(self, Prec.none);
        u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len,
            &self.child_buf_capacity, self.allocator, val);
        if (parserPeek(self).kind == TokenKind.comma) _ = parserAdvance(self);
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var gap: []const u8 = "";
    _ = gap;
    var payload: u64 = 0;
    if (self.child_buf_len > saved_child_len) {
        payload = ast_mod.astStoreAddExtraChildren(self.store,
            self.child_buf_items[saved_child_len..self.child_buf_len]);
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
    var capture_node: u32 = 0;
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
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
        capture_node = ast_mod.astStoreAddNode(self.store, AstKind.if_capture, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            0, 0, 0, name_id);
    }
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
        kw.span_start, end_pos, cond, then_body, else_body, capture_node);
}

pub fn parserParseSwitchExpr(self: *Parser) ParserError!u32 {
    var kw_tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var cond: u32 = try parserParseExprPrec(self, Prec.assignment);
    _ = try parserExpect(self, TokenKind.rparen);
    _ = try parserExpect(self, TokenKind.lbrace);

    var saved_switch: usize = self.child_buf_len;
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

    var payload: u64 = 0;
    if (self.child_buf_len > saved_switch) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[saved_switch..self.child_buf_len]);
    }
    self.child_buf_len = saved_switch;
    var end_pos: u32 = kw_tok.span_start + @intCast(u32, kw_tok.span_len);
    var pswe_node = ast_mod.astStoreAddNode(self.store, AstKind.swt_ex, 0,
        kw_tok.span_start, end_pos, cond, 0, 0, payload);
    var pswe_b: [10]u8 = undefined; var pswe_l = itoa_mod.itoa(pswe_node, pswe_b[0..]); var pswe_s: usize = @intCast(usize, 9) - @intCast(usize, pswe_l); var pswe_m: []const u8 = "PSWE:n"; pal.markerWrite(pswe_m); pal.markerWrite(pswe_b[pswe_s..@intCast(usize, 9)]); var pswe_pm: []const u8 = "p"; pal.markerWrite(pswe_pm); var pswe_pb: [10]u8 = undefined; var pswe_pl = itoa_mod.itoa(@intCast(u32, payload & @intCast(u64, 0xFFFFFFFF)), pswe_pb[0..]); var pswe_ps: usize = @intCast(usize, 9) - @intCast(usize, pswe_pl); pal.markerWrite(pswe_pb[pswe_ps..@intCast(usize, 9)]); var pswe_nl: []const u8 = "\n"; pal.markerWrite(pswe_nl);
    return pswe_node;
}

fn parserParseSwitchProng(self: *Parser) ParserError!u32 {
    var start_tok = parserPeek(self);
    var case_items: [*]u32 = undefined;
    var case_len: usize = 0;
    var case_cap: usize = 0;
    var is_else: u8 = 0;

    if (parserPeek(self).kind == TokenKind.kw_else) {
        var pcb_tm: []const u8 = "PCB:T"; pal.markerWriteInt(pcb_tm, @intCast(u32, @enumToInt(parserPeek(self).kind)));
        _ = parserAdvance(self);
        is_else = 1;
    } else {
        var pcb_em: []const u8 = "PCB:E"; pal.markerWrite(pcb_em);
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
                u32ArrayListAppendInner(&case_items, &case_len, &case_cap, self.allocator, range_node);
            } else {
                u32ArrayListAppendInner(&case_items, &case_len, &case_cap, self.allocator, item);
                var pcb2_m: []const u8 = "PCB:B"; pal.markerWriteInt(pcb2_m, @intCast(u32, case_len));
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
        var cpm: []const u8 = "CPT:n"; pal.markerWrite(cpm);
        var cpnb: [10]u8 = undefined; var cpnl = itoa_mod.itoa(capture_name, cpnb[0..]); var cpns: usize = @intCast(usize, 9) - @intCast(usize, cpnl); pal.markerWrite(cpnb[cpns..@intCast(usize, 9)]);
        var cpem: []const u8 = "\n"; pal.markerWrite(cpem);
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

    var pcb_m: []const u8 = "PCB:n"; pal.markerWrite(pcb_m);
    var pcb_nb: [10]u8 = undefined; var pcb_nl = itoa_mod.itoa(@intCast(u32, case_len), pcb_nb[0..]); var pcb_ns: usize = @intCast(usize, 9) - @intCast(usize, pcb_nl); pal.markerWrite(pcb_nb[pcb_ns..@intCast(usize, 9)]);
    var pcb_pm: []const u8 = "p="; pal.markerWrite(pcb_pm);
    var pcb_pb: [10]u8 = undefined; var pcb_pl = itoa_mod.itoa(flags, pcb_pb[0..]); var pcb_ps: usize = @intCast(usize, 9) - @intCast(usize, pcb_pl); pal.markerWrite(pcb_pb[pcb_ps..@intCast(usize, 9)]);
    var pcb_n: []const u8 = "\n"; pal.markerWrite(pcb_n);
    var pcb_sm: []const u8 = "PCB:S"; pal.markerWriteInt(pcb_sm, @intCast(u32, case_len));
    var items_payload: u64 = ast_mod.astStoreAddExtraChildren(self.store, case_items[0..case_len]);
    var ppl_m: []const u8 = "PPL:n"; pal.markerWrite(ppl_m);
    var ppl_pb: [10]u8 = undefined; var ppl_pl = itoa_mod.itoa(@intCast(u32, items_payload & @intCast(u64, 0xFFFFFFFF)), ppl_pb[0..]); var ppl_ps: usize = @intCast(usize, 9) - @intCast(usize, ppl_pl); pal.markerWrite(ppl_pb[ppl_ps..@intCast(usize, 9)]);
    var ppl_n: []const u8 = "\n"; pal.markerWrite(ppl_n);
    var end_pos: u32 = start_tok.span_start + @intCast(u32, start_tok.span_len);
    return ast_mod.astStoreAddNode(self.store, AstKind.swt_prong, flags,
        start_tok.span_start, end_pos, body, capture_name, 0, items_payload);
}

pub fn parserParseType(self: *Parser) ParserError!u32 {
    var tok = parserPeek(self);
    if (tok.kind == TokenKind.star) return parserParsePtrType(self);
    if (tok.kind == TokenKind.lbracket) return parserParseBracketType(self);
    if (tok.kind == TokenKind.question_mark) return parserParseOptionalType(self);
    if (tok.kind == TokenKind.bang) return parserParseErrorUnionType(self);
    if (tok.kind == TokenKind.kw_fn) return parserParseFnType(self);
    if (tok.kind == TokenKind.kw_error) {
        var es = try parserParseErrorSetDecl(self);
        if (parserPeek(self).kind == TokenKind.bang) {
            _ = parserAdvance(self);
            var payload = try parserParseType(self);
            return ast_mod.astStoreAddNode(self.store, AstKind.error_union_type, 0,
                tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
                es, payload, 0, 0);
        }
        return es;
    }
    if (tok.kind == TokenKind.kw_struct) return parserParseStructType(self);
    if (tok.kind == TokenKind.kw_enum) return parserParseEnumType(self);
    if (tok.kind == TokenKind.kw_union) return parserParseUnionType(self);
    if (tok.kind == TokenKind.kw_anytype) { _ = parserAdvance(self); var z: u32 = @intCast(u32, 0); return z; }
    var base = try parserParseTypeName(self);
    if (parserPeek(self).kind == TokenKind.bang) {
        _ = parserAdvance(self);
        var payload = try parserParseType(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.error_union_type, 0,
            tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
            base, payload, 0, 0);
    }
    return base;
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
        0, payload, 0, 0);
}

fn parserParseFnType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var param_buf: [*]u32 = undefined;
    var param_count: usize = 0;
    var param_cap: usize = @intCast(usize, 0);
    while (parserPeek(self).kind != TokenKind.rparen) {
        if (parserPeek(self).kind == TokenKind.dot_dot_dot) {
            var vtok = parserAdvance(self);
            var v_msg: []const u8 = "varargs not allowed in function pointer types";
            parserAddError(self, vtok, v_msg);
            return error.UnexpectedToken;
        }
        if (parserPeek(self).kind == TokenKind.identifier and parserPeekN(self, 1).kind == TokenKind.colon) {
            _ = parserAdvance(self);
            _ = try parserExpect(self, TokenKind.colon);
        }
        var p = try parserParseType(self);
        parserPushU32(self, &param_buf, &param_count, &param_cap, p);
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
    var payload: u64 = 0;
    if (param_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, param_buf[0..param_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_type, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        ret_type, 0, 0, payload);
}

fn parserParseErrorSetDecl(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    return parserParseErrorSetDeclBody(self, tok);
}

fn parserParseErrorSetDeclBody(self: *Parser, kw: Token) ParserError!u32 {
    _ = try parserExpect(self, TokenKind.lbrace);
    var member_buf: [*]u32 = null;
    var member_count: usize = 0;
    var member_cap: usize = @intCast(usize, 0);
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var tag_tok = try parserExpect(self, TokenKind.identifier);
        var pt = ParseToken{ .kind = tag_tok.kind, .span_start = tag_tok.span_start, .span_len = tag_tok.span_len };
        var tag_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
        parserPushU32(self, &member_buf, &member_count, &member_cap, tag_id);
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (member_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, member_buf[0..member_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.error_set_decl, 0,
        kw.span_start, kw.span_start + @intCast(u32, kw.span_len),
        0, 0, 0, payload);
}

fn parserParseStructType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lbrace);
    var fields_buf: [*]u32 = undefined;
    var fields_count: usize = 0;
    var fields_cap: usize = @intCast(usize, 0);
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var name_tok = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.colon);
        var npt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, npt));
        var field_type = try parserParseType(self);
        var field_node = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            field_type, 0, 0, name_id);
        parserPushU32(self, &fields_buf, &fields_count, &fields_cap, field_node);
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (fields_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, fields_buf[0..fields_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.struct_decl, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        0, 0, 0, payload);
}

fn parserParseEnumType(self: *Parser) ParserError!u32 {
    var tok = parserAdvance(self);
    var backing_type2: u32 = 0;
    if (parserPeek(self).kind == TokenKind.lparen) {
        _ = parserAdvance(self);
        backing_type2 = try parserParseType(self);
        _ = try parserExpect(self, TokenKind.rparen);
    }
    _ = try parserExpect(self, TokenKind.lbrace);
    var members_buf: [*]u32 = undefined;
    var members_count: usize = 0;
    var members_cap: usize = @intCast(usize, 0);
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var name_tok = try parserExpect(self, TokenKind.identifier);
        var mpt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, mpt));
        var value_expr: u32 = 0;
        if (parserPeek(self).kind == TokenKind.eq) {
            _ = parserAdvance(self);
            value_expr = try parserParseExprPrec(self, Prec.assignment);
        }
        var mnode = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
            name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
            0, value_expr, 0, name_id);
        parserPushU32(self, &members_buf, &members_count, &members_cap, mnode);
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (members_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, members_buf[0..members_count]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.enum_decl, 0,
        tok.span_start, tok.span_start + @intCast(u32, tok.span_len),
        backing_type2, 0, 0, payload);
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
    var fields_buf: [*]u32 = undefined;
    var fields_count: usize = 0;
    var fields_cap: usize = @intCast(usize, 0);
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
        } else {
            field_node = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
                name_tok.span_start, name_tok.span_start + @intCast(u32, name_tok.span_len),
                0, 0, 0, name_id);
        }
        parserPushU32(self, &fields_buf, &fields_count, &fields_cap, field_node);
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    _ = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
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
    var pstk_m: []const u8 = "PSTK:k"; pal.markerWrite(pstk_m); var pstk_b: [10]u8 = undefined; var pstk_l = itoa_mod.itoa(@intCast(u32, @enumToInt(tok.kind)), pstk_b[0..]); var pstk_s: usize = @intCast(usize, 9) - @intCast(usize, pstk_l); pal.markerWrite(pstk_b[pstk_s..@intCast(usize, 9)]); var pstk_nl: []const u8 = "\n"; pal.markerWrite(pstk_nl);
    if (tok.kind == TokenKind.kw_const) { var varc_s: []const u8 = "VARC"; pal.markerWrite(varc_s); return parserParseVarDecl(self, false, false, false); }
    if (tok.kind == TokenKind.kw_var) { var varv_s: []const u8 = "VARV"; pal.markerWrite(varv_s); return parserParseVarDecl(self, true, false, false); }
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
    self.decl_buf_len = @intCast(usize, 0);

    while (parserPeek(self).kind != TokenKind.eof) {
        var decl = parserParseStatement(self) catch {
            var tok = parserPeek(self);
            var err_msg: []const u8 = "unexpected token";
            var err = parserEmitErrorNode(self, tok, err_msg);
            parserSynchronize(self);
            u32ArrayListAppendInner(&self.decl_buf_items, &self.decl_buf_len, &self.decl_buf_capacity, self.allocator, err);
            while (parserPeek(self).kind == TokenKind.semicolon) _ = parserAdvance(self);
            continue;
        };
        u32ArrayListAppendInner(&self.decl_buf_items, &self.decl_buf_len, &self.decl_buf_capacity, self.allocator, decl);
    }

    var payload: u64 = 0;
    if (self.decl_buf_len > @intCast(usize, 0)) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, self.decl_buf_items[0..self.decl_buf_len]);
    }
    return ast_mod.astStoreAddNode(self.store, AstKind.module_root, 0, 0, 0, 0, 0, 0, payload);
}

fn parserParseExprStmt(self: *Parser) ParserError!u32 {
    var result = try parserParseExprPrec(self, Prec.assignment);
    if (parserPeek(self).kind != TokenKind.rbrace) {
        _ = try parserExpect(self, TokenKind.semicolon);
    }
    return result;
}

fn parserParseLabeledStmt(self: *Parser) ParserError!u32 {
    var label_tok = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.colon);
    var inner = try parserParseStatement(self);
    var end = inner; _ = end;
    return ast_mod.astStoreAddNode(self.store, AstKind.labeled_stmt, 0,
        label_tok.span_start, label_tok.span_start + @intCast(u32, label_tok.span_len),
        inner, 0, 0, label_tok.value.string_id);
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
        label_tok.span_start, end_pos, body, 0, 0, label_tok.value.string_id);
}

fn parserParseVarDecl(self: *Parser, is_mutable: bool, is_pub: bool, is_extern: bool) ParserError!u32 {
    var vmsg: []const u8 = "V"; pal.markerWrite(vmsg);
    var kw = parserAdvance(self);
    var name_raw = parserPeek(self);
    if (name_raw.kind == TokenKind.underscore) {
        _ = parserAdvance(self);
    } else {
        _ = try parserExpect(self, TokenKind.identifier);
    }
    var name_id = name_raw.value.string_id;
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
    var end_pos: u32 = semi.span_start + @intCast(u32, semi.span_len);
    var vok: []const u8 = "v"; pal.markerWrite(vok);
    var pdv_s: []const u8 = "PDVx"; pal.markerWrite(pdv_s);
    if (init_node != @intCast(u32, 0)) {
        var init_check = self.store.nodes.items[@intCast(usize, init_node)];
        if (init_check.kind == AstKind.c_include) {
            return init_node;
        }
    }
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
    var fmsg: []const u8 = "Fv"; pal.markerWrite(fmsg);
    var kw = parserAdvance(self);
    var flags: u8 = 0;
    if (is_pub) flags = flags | @intCast(u8, 0x02);
    if (is_extern) flags = flags | @intCast(u8, 0x04);
    if (is_test) flags = flags | @intCast(u8, 0x20);

    var name_tok = try parserExpect(self, TokenKind.identifier);
    _ = try parserExpect(self, TokenKind.lparen);

    self.child_buf_len = 0;
    while (parserPeek(self).kind != TokenKind.rparen and parserPeek(self).kind != TokenKind.eof) {
        if (parserPeek(self).kind == TokenKind.dot_dot_dot) {
            _ = parserAdvance(self);
            flags = flags | @intCast(u8, 0x01);
            break;
        }
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

    var param_start: u32 = 0;
    var param_count: u16 = @intCast(u16, 0);
    if (self.child_buf_len > @intCast(usize, 0)) {
        var pp = ast_mod.astStoreAddExtraChildren(self.store, self.child_buf_items[0..self.child_buf_len]);
        param_start = @intCast(u32, pp >> 32);
        param_count = @intCast(u16, self.child_buf_len);
        self.child_buf_len = 0;
    }

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

    if (self.child_buf_len > @intCast(usize, 0)) {
        var dmsg: []const u8 = "DP:child_buf_stale\n"; pal.markerWrite(dmsg);
    }

    var name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self,
        ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len }));
    var pmsg: []const u8 = "P:";
    pal.markerWrite(pmsg);
    var pa_buf: [20]u8 = undefined;
    var pa_val: u32 = @intCast(u32, param_count);
    var pa_len = itoa_mod.itoa(pa_val, pa_buf[0..]);
    var pa_start: usize = @intCast(usize, 19) - @intCast(usize, pa_len);
    pal.markerWrite(pa_buf[pa_start .. @intCast(usize, 19)]);
    var pnl: []const u8 = "\n";
    pal.markerWrite(pnl);
    var proto: FnProto = FnProto{ .name_id = name_id, .params_start = param_start, .params_count = param_count, .return_type_node = ret_type_node };
    var proto_idx: u32 = ast_mod.astStoreAddFnProto(self.store, proto);
    self.child_buf_len = 0;
    var fok: []const u8 = "Fk"; pal.markerWrite(fok);
    return ast_mod.astStoreAddNode(self.store, AstKind.fn_decl, flags, kw.span_start, end_pos, body_node, 0, 0, proto_idx);
}

fn parserParseIfStmt(self: *Parser) ParserError!u32 {
    var kw = parserAdvance(self);
    _ = try parserExpect(self, TokenKind.lparen);
    var cond = try parserParseExprPrec(self, Prec.none);
    var pc0: []const u8 = "PIF:c="; pal.markerWrite(pc0);
    var pc0b: [10]u8 = undefined; var pc0l = itoa_mod.itoa(cond, pc0b[0..]); var pc0s: usize = @intCast(usize, 9) - @intCast(usize, pc0l); pal.markerWrite(pc0b[pc0s..@intCast(usize, 9)]);
    var pck: []const u8 = "k"; pal.markerWrite(pck);
    var cond_n = self.store.nodes.items[@intCast(usize, cond)];
    var pckb: [10]u8 = undefined; var pckl = itoa_mod.itoa(cond_n.kind, pckb[0..]); var pcks: usize = @intCast(usize, 9) - @intCast(usize, pckl); pal.markerWrite(pckb[pcks..@intCast(usize, 9)]);
    var pc1: []const u8 = "c1"; pal.markerWrite(pc1);
    var pc1b: [10]u8 = undefined; var pc1l = itoa_mod.itoa(cond_n.child_0, pc1b[0..]); var pc1s: usize = @intCast(usize, 9) - @intCast(usize, pc1l); pal.markerWrite(pc1b[pc1s..@intCast(usize, 9)]);
    var pc2: []const u8 = "c2"; pal.markerWrite(pc2);
    var pc2b: [10]u8 = undefined; var pc2l = itoa_mod.itoa(cond_n.child_1, pc2b[0..]); var pc2s: usize = @intCast(usize, 9) - @intCast(usize, pc2l); pal.markerWrite(pc2b[pc2s..@intCast(usize, 9)]);
    var pck1: []const u8 = "k1"; pal.markerWrite(pck1);
    var cn1 = self.store.nodes.items[@intCast(usize, cond_n.child_0)];
    var pck1b: [10]u8 = undefined; var pck1l = itoa_mod.itoa(cn1.kind, pck1b[0..]); var pck1s: usize = @intCast(usize, 9) - @intCast(usize, pck1l); pal.markerWrite(pck1b[pck1s..@intCast(usize, 9)]);
    var pck2: []const u8 = "k2"; pal.markerWrite(pck2);
    var cn2 = self.store.nodes.items[@intCast(usize, cond_n.child_1)];
    var pck2b: [10]u8 = undefined; var pck2l = itoa_mod.itoa(cn2.kind, pck2b[0..]); var pck2s: usize = @intCast(usize, 9) - @intCast(usize, pck2l); pal.markerWrite(pck2b[pck2s..@intCast(usize, 9)]);
    var pknl: []const u8 = "\n"; pal.markerWrite(pknl);
    _ = try parserExpect(self, TokenKind.rparen);

    var capture_node: u32 = 0;
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

    var pif_m: []const u8 = "PIF:b"; pal.markerWrite(pif_m); var pif_b: [10]u8 = undefined; var pif_l = itoa_mod.itoa(then_body, pif_b[0..]); var pif_s: usize = @intCast(usize, 9) - @intCast(usize, pif_l); pal.markerWrite(pif_b[pif_s..@intCast(usize, 9)]); var pif_km: []const u8 = "k"; pal.markerWrite(pif_km); var pif_kb: [10]u8 = undefined; var pif_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(self.store.nodes.items[@intCast(usize, then_body)].kind)), pif_kb[0..]); var pif_ks: usize = @intCast(usize, 9) - @intCast(usize, pif_kl); pal.markerWrite(pif_kb[pif_ks..@intCast(usize, 9)]); var pif_nl: []const u8 = "\n"; pal.markerWrite(pif_nl);

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
    if (parserPeek(self).kind == TokenKind.semicolon) {
        _ = parserAdvance(self);
        if (parserPeek(self).kind == TokenKind.kw_else) {
            var else_tok = parserPeek(self);
            var else_msg: []const u8 = "';' not allowed before 'else' - use braces: if (cond) { ... } else { ... }";
            parserAddError(self, else_tok, else_msg);
            return error.UnexpectedToken;
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
    var cap_node: u32 = 0;
    if (parserPeek(self).kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var cap_tok: ParseToken = undefined;
        if (parserPeek(self).kind == TokenKind.underscore) {
            cap_tok = try parserExpect(self, TokenKind.underscore);
        } else {
            cap_tok = try parserExpect(self, TokenKind.identifier);
        }
        capture_name = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, cap_tok));
        cap_node = ast_mod.astStoreAddNode(self.store, AstKind.while_capture, 0,
            cap_tok.span_start, cap_tok.span_start + @intCast(u32, cap_tok.span_len), 0, 0, 0, capture_name);
        _ = try parserExpect(self, TokenKind.pipe);
    }

    var continue_expr: u32 = 0;
    if (parserPeek(self).kind == TokenKind.colon) {
        _ = parserAdvance(self);
        _ = try parserExpect(self, TokenKind.lparen);
        continue_expr = try parserParseExprPrec(self, Prec.none);
        _ = try parserExpect(self, TokenKind.rparen);
    }

    var body: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.lbrace) {
        body = try parserParseBlock(self);
    } else {
        body = try parserParseExprPrec(self, Prec.assignment);
    }
    if (parserPeek(self).kind == TokenKind.semicolon) {
        _ = parserAdvance(self);
    }
    var end_pos: u32 = undefined;
    if (self.pos > 0) {
        var last = self.tokens_ptr[self.pos - 1];
        end_pos = last.span_start + @intCast(u32, last.span_len);
    } else end_pos = kw.span_start;
    var zzz_sz = "ZZZ_ASTNODE_SZ_24_BEFORE_WHILESTMT_ASTSTOREADDNODE";
    var zzz_buf_c2: [10]u8 = undefined; var zzz_c2e_m: []const u8 = "PTC2:e"; pal.markerWrite(zzz_c2e_m); var zzz_c2e_l = itoa_mod.itoa(continue_expr, zzz_buf_c2[0..]); var zzz_c2e_s: usize = @intCast(usize, 9) - @intCast(usize, zzz_c2e_l); pal.markerWrite(zzz_buf_c2[zzz_c2e_s..@intCast(usize, 9)]); var zzz_c2e_nl: []const u8 = "\n"; pal.markerWrite(zzz_c2e_nl);
    var zzz_c2 = continue_expr;
    return ast_mod.astStoreAddNode(self.store, AstKind.while_stmt, 0,
        kw.span_start, end_pos, cond, body, zzz_c2, cap_node);
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

    var body: u32 = undefined;
    if (parserPeek(self).kind == TokenKind.lbrace) {
        body = try parserParseBlock(self);
    } else {
        body = try parserParseExprPrec(self, Prec.assignment);
    }
    if (parserPeek(self).kind == TokenKind.semicolon) {
        _ = parserAdvance(self);
    }
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
    var nt = parserPeek(self).kind;
    if (nt != TokenKind.semicolon and nt != TokenKind.comma and nt != TokenKind.rbrace and nt != TokenKind.eof) {
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
    var backing_type: u32 = 0;
    if (kind == AstKind.union_decl and parserPeek(self).kind == TokenKind.lparen) {
        _ = parserAdvance(self);
        _ = try parserExpect(self, TokenKind.kw_enum);
        _ = try parserExpect(self, TokenKind.rparen);
        is_tagged = 1;
    }
    if (kind == AstKind.enum_decl and parserPeek(self).kind == TokenKind.lparen) {
        _ = parserAdvance(self);
        backing_type = try parserParseType(self);
        _ = try parserExpect(self, TokenKind.rparen);
    }
    if (parserPeek(self).kind == TokenKind.identifier) {
        var name_tok = parserAdvance(self);
        var pt = ParseToken{ .kind = name_tok.kind, .span_start = name_tok.span_start, .span_len = name_tok.span_len };
        name_id = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, pt));
    }
    _ = try parserExpect(self, TokenKind.lbrace);
    var fields_buf: [*]u32 = undefined;
    var fields_count: usize = 0;
    var fields_cap: usize = @intCast(usize, 0);
    while (parserPeek(self).kind != TokenKind.rbrace) {
        var ftok = try parserExpect(self, TokenKind.identifier);
        var fpt = ParseToken{ .kind = ftok.kind, .span_start = ftok.span_start, .span_len = ftok.span_len };
        var fid = string_interner_mod.stringInternerIntern(self.interner, parserTokenText(self, fpt));
        if (kind == AstKind.enum_decl) {
            var ev: u32 = 0;
            if (parserPeek(self).kind == TokenKind.eq) {
                _ = parserAdvance(self);
                ev = try parserParseExprPrec(self, Prec.assignment);
            }
            var enode = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
                ftok.span_start, ftok.span_start + @intCast(u32, ftok.span_len),
                0, ev, 0, fid);
            parserPushU32(self, &fields_buf, &fields_count, &fields_cap, enode);
        } else {
            _ = try parserExpect(self, TokenKind.colon);
            var ftype = try parserParseType(self);
            var fnode = ast_mod.astStoreAddNode(self.store, AstKind.field_decl, 0,
                ftok.span_start, ftok.span_start + @intCast(u32, ftok.span_len),
                ftype, 0, 0, fid);
            parserPushU32(self, &fields_buf, &fields_count, &fields_cap, fnode);
        }
        if (parserPeek(self).kind == TokenKind.comma) {
            _ = parserAdvance(self);
        }
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (fields_count > 0) {
        payload = ast_mod.astStoreAddExtraChildren(self.store, fields_buf[0..fields_count]);
    }
    var end_pos: u32 = rbrace.span_start + @intCast(u32, rbrace.span_len);
    return ast_mod.astStoreAddNode(self.store, kind, is_tagged,
        tok.span_start, end_pos, name_id, backing_type, 0, payload);
}
fn parserParseBlock(self: *Parser) ParserError!u32 {
    var lbrace = try parserExpect(self, TokenKind.lbrace);
    var saved_len: usize = self.child_buf_len;
    var local_buf: [64]u32 = undefined;
     var local_len: usize = @intCast(usize, 0);
     while (parserPeek(self).kind != TokenKind.rbrace and parserPeek(self).kind != TokenKind.eof) {
         var stmt = try parserParseStatement(self);
         if (local_len < @intCast(usize, 64)) {
             local_buf[@intCast(usize, local_len)] = stmt;
         } else {
             if (local_len == @intCast(usize, 64)) {
                 var fi: usize = @intCast(usize, 0);
                 while (fi < @intCast(usize, 64)) : (fi += @intCast(usize, 1)) {
                     u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, local_buf[fi]);
                 }
             }
             u32ArrayListAppendInner(&self.child_buf_items, &self.child_buf_len, &self.child_buf_capacity, self.allocator, stmt);
         }
          local_len += @intCast(usize, 1);
          var pk = parserPeek(self);
          var pbx_sm: []const u8 = "PBX:S"; pal.markerWriteInt(pbx_sm, @intCast(u32, local_len));
          var pbx_tm: []const u8 = "PBX:T"; pal.markerWriteInt(pbx_tm, @intCast(u32, @enumToInt(pk.kind)));
          var pbx_km: []const u8 = "PBX:K"; pal.markerWriteInt(pbx_km, @intCast(u32, @enumToInt(self.store.nodes.items[@intCast(usize, stmt)].kind)));
          if (pk.kind == TokenKind.rbrace or pk.kind == TokenKind.eof) {
              var pbx_lm: []const u8 = "PBX:L"; pal.markerWriteInt(pbx_lm, @intCast(u32, local_len));
              var pbx_bm: []const u8 = "PBX:B"; pal.markerWriteInt(pbx_bm, @intCast(u32, saved_len));
              var pbx_pm: []const u8 = "PBX:P"; pal.markerWriteInt(pbx_pm, lbrace.span_start);
          }
    }
    var rbrace = try parserExpect(self, TokenKind.rbrace);
    var payload: u64 = 0;
    if (local_len > @intCast(usize, 0)) {
        var slice: []u32 = undefined;
        if (local_len <= @intCast(usize, 64)) {
            slice = local_buf[0..local_len];
        } else {
            slice = self.child_buf_items[saved_len..saved_len + local_len];
        }
        payload = ast_mod.astStoreAddExtraChildren(self.store, slice);
    }
    self.child_buf_len = saved_len;
    var plen_m: []const u8 = "PLEN:l"; pal.markerWrite(plen_m); var plen_lb: [10]u8 = undefined; var plen_ll = itoa_mod.itoa(@intCast(u32, local_len), plen_lb[0..]); var plen_ls: usize = @intCast(usize, 9) - @intCast(usize, plen_ll); pal.markerWrite(plen_lb[plen_ls..@intCast(usize, 9)]); var plen_pm: []const u8 = "p"; pal.markerWrite(plen_pm); var plen_pb: [10]u8 = undefined; var plen_pl = itoa_mod.itoa(@intCast(u32, payload & @intCast(u64, 0xFFFFFFFF)), plen_pb[0..]); var plen_ps: usize = @intCast(usize, 9) - @intCast(usize, plen_pl); pal.markerWrite(plen_pb[plen_ps..@intCast(usize, 9)]); var plen_nl: []const u8 = "\n"; pal.markerWrite(plen_nl);
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
        kind == TokenKind.caret_eq or kind == TokenKind.plus_pct_eq or
        kind == TokenKind.minus_pct_eq or kind == TokenKind.star_pct_eq or
        kind == TokenKind.plus_pipe_eq or kind == TokenKind.minus_pipe_eq or
        kind == TokenKind.star_pipe_eq or kind == TokenKind.shl_pipe_eq) return OpInfo{ .prec = Prec.assignment, .right_assoc = true };

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
    if (kind == TokenKind.shl or kind == TokenKind.shr or
        kind == TokenKind.shl_pipe) return OpInfo{ .prec = Prec.shift, .right_assoc = false };
    if (kind == TokenKind.plus or kind == TokenKind.minus or
        kind == TokenKind.plus_pct or kind == TokenKind.minus_pct or
        kind == TokenKind.plus_pipe or kind == TokenKind.minus_pipe) return OpInfo{ .prec = Prec.additive, .right_assoc = false };
    if (kind == TokenKind.star or kind == TokenKind.slash or kind == TokenKind.percent or
        kind == TokenKind.star_pct or kind == TokenKind.star_pipe) return OpInfo{ .prec = Prec.multiply, .right_assoc = false };

    return null;
}
