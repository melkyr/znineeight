const TokenKind = @import("../token.zig").TokenKind;
const Token = @import("../token.zig").Token;
const TokenValue = @import("../token.zig").TokenValue;
const AstNode = @import("../ast.zig").AstNode;
const parser_mod = @import("../parser.zig");
const ast_mod = @import("../ast.zig");
const AstKind = ast_mod.AstKind;
const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const lexer_mod = @import("../lexer.zig");

fn assertEqU32(actual: u32, expected: u32) void {
    if (actual != expected) @panic("assertEqU32 failed");
}

pub fn runParserUnitTests() void {
    testPrecEnumValues();
    testPrecToInt();
    testPrecFromInt();
    testGetInfixInfoReturnsAssignment();
    testGetInfixInfoReturnsNull();
    testGetInfixInfoReturnsRightAssoc();
    testSwitchExprBasic();
    testSwitchExprRange();
    testSwitchProngCapture();
    testSwitchStmtWrapsExpr();
    testParseTypePtr();
    testParseTypeVoid();
    testTypeVoid();
    testTypePtrConst();
    testTypeSlice();
    testTypeManyPtr();
    testTypeArray();
    testTypeOptional();
    testTypeErrorUnion();
    testTypeFn();
    testParseImportExpr();
    testParserErrorRecovery();
    testParseModuleRootEmpty();
    testParseModuleRootVarDecl();
    testParseQualifiedImport();
    testParseErrorLiteral();
    testParseTryExpr();
    testParseIfExpr();
    testParseBlockExpr();
    testParseCatchBlock();
    testParseOrelseBlock();
    testParseArrayLiteral();
    testParseExternFn();
    testParseStructInitVarDecl();
    testParseAnonStructInit();
    testParsePositionalTuple();
    testParseEnumTypeAsExpr();
    testParseLabeledBreak();
    testGapB_IfExprBody();
    testGapC_ReturnExpr();
    testGapC_BreakExpr();
    testGapC_SwitchBreak();
    testGapB_IfExprBody_Chain();
    testGapC_ReturnError();
    testForRange();
    testDiscardStmt();
    testSwitchUnderscoreCapture();
    testForUnderscoreCapture();
    testLabeledBlockExpr();
}

fn testPrecEnumValues() void {
    assertEqU32(@intCast(u32, @enumToInt(Prec.none)), @intCast(u32, 0));
    assertEqU32(@intCast(u32, @enumToInt(Prec.assignment)), @intCast(u32, 1));
    assertEqU32(@intCast(u32, @enumToInt(Prec.multiply)), @intCast(u32, 12));
    assertEqU32(@intCast(u32, @enumToInt(Prec.prefix)), @intCast(u32, 13));
}

fn testPrecToInt() void {
    assertEqU32(@intCast(u32, parser_mod.precToInt(Prec.none)), @intCast(u32, 0));
    assertEqU32(@intCast(u32, parser_mod.precToInt(Prec.assignment)), @intCast(u32, 1));
    assertEqU32(@intCast(u32, parser_mod.precToInt(Prec.multiply)), @intCast(u32, 12));
}

fn testPrecFromInt() void {
    assertEqU32(@intCast(u32, @enumToInt(parser_mod.precFromInt(@intCast(u8, 0)))), @intCast(u32, 0));
    assertEqU32(@intCast(u32, @enumToInt(parser_mod.precFromInt(@intCast(u8, 1)))), @intCast(u32, 1));
    assertEqU32(@intCast(u32, @enumToInt(parser_mod.precFromInt(@intCast(u8, 12)))), @intCast(u32, 12));
}

const Prec = parser_mod.Prec;
const OpInfo = parser_mod.OpInfo;

fn testGetInfixInfoReturnsAssignment() void {
    var info = parser_mod.getInfixInfo(TokenKind.eq);
    if (info == null) {
        @panic("getInfixInfo(eq) should not be null");
    }
}

fn testGetInfixInfoReturnsNull() void {
    if (!(parser_mod.getInfixInfo(TokenKind.semicolon) == null)) {
        @panic("getInfixInfo(semicolon) should be null");
    }
}

fn testGetInfixInfoReturnsRightAssoc() void {
    var info = parser_mod.getInfixInfo(TokenKind.kw_orelse);
    if (info == null) {
        @panic("getInfixInfo(orelse) should not be null");
    }
}

fn lexAndSwitch(src: []const u8) parser_mod.ParserError!u32 {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(src, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], src, &store, &in_, &d, &a);
    var node_idx = try parser_mod.parserParseSwitchExpr(&p);
    _ = store;
    return node_idx;
}

fn testSwitchExprBasic() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "switch (x) { 1 => true, else => false }";
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseSwitchExpr(&p) catch unreachable;

    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.switch_expr)));

    if (node.payload > @intCast(u32, 0)) {
        var prongs = ast_mod.astStoreGetExtraChildren(&store, node.payload);
        if (prongs.len > @intCast(usize, 0)) {
            var prong0 = store.nodes.items[prongs[0]];
            assertEqU32(@intCast(u32, @enumToInt(prong0.kind)), @intCast(u32, @enumToInt(AstKind.switch_prong)));
        }
        if (prongs.len > @intCast(usize, 1)) {
            var prong1 = store.nodes.items[prongs[1]];
            assertEqU32(@intCast(u32, @enumToInt(prong1.kind)), @intCast(u32, @enumToInt(AstKind.switch_prong)));
        }
    }
}

fn testSwitchExprRange() void {
    var s: []const u8 = "switch (x) { 0..5 => true, else => false }";
    var idx = (lexAndSwitch(s) catch unreachable);
    _ = idx;
}

fn testSwitchProngCapture() void {
    var s: []const u8 = "switch (x) { 1, 2 => |val| val, else => 0 }";
    var idx = (lexAndSwitch(s) catch unreachable);
    _ = idx;
}

fn testSwitchStmtWrapsExpr() void {
    var s: []const u8 = "switch (x) { 1 => {} }";
    var idx = (lexAndSwitch(s) catch unreachable);
    _ = idx;
}

fn testParseTypePtr() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "*const u32";
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseType(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.ptr_type)));
}

fn testParseTypeVoid() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "void";
    var tokens: [8]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 8) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseType(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.ident_expr)));
}

fn lexAndTypeKind(src: []const u8) u32 {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(src, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseType(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    return @intCast(u32, @enumToInt(node.kind));
}

fn testTypeVoid() void {
    var s: []const u8 = "void";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.ident_expr)));
}
fn testTypePtrConst() void {
    var s: []const u8 = "*const u32";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.ptr_type)));
}
fn testTypeSlice() void {
    var s: []const u8 = "[]u8";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.slice_type)));
}
fn testTypeManyPtr() void {
    var s: []const u8 = "[*]u8";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.many_ptr_type)));
}
fn testTypeArray() void {
    var s: []const u8 = "[4]u8";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.array_type)));
}
fn testTypeOptional() void {
    var s: []const u8 = "?u32";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.optional_type)));
}
fn testTypeErrorUnion() void {
    var s: []const u8 = "!void";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.error_union_type)));
}
fn testTypeFn() void {
    var s: []const u8 = "fn(u32) void";
    assertEqU32(lexAndTypeKind(s), @intCast(u32, @enumToInt(AstKind.fn_type)));
}
fn testParseImportExpr() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var imp_s: []const u8 = "import";
    var path_s: []const u8 = "foo.zig";
    var import_id = interner_mod.stringInternerIntern(&in_, imp_s);
    var path_id = interner_mod.stringInternerIntern(&in_, path_s);
    var tokens: [4]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.builtin_identifier, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 7), .value = TokenValue{ .string_id = import_id } };
    tokens[1] = Token{ .kind = TokenKind.lparen, .span_start = @intCast(u32, 7), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[2] = Token{ .kind = TokenKind.string_literal, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 9), .value = TokenValue{ .string_id = path_id } };
    tokens[3] = Token{ .kind = TokenKind.rparen, .span_start = @intCast(u32, 17), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "@import(         )";
    var p = parser_mod.parserInit(tokens[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseExprPrec(&p, Prec.assignment) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.import_expr)));
    assertEqU32(node.payload, path_id);
}
fn testParserErrorRecovery() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var x_s: []const u8 = "x";
    var y_s: []const u8 = "y";
    var x_id = interner_mod.stringInternerIntern(&in_, x_s);
    var y_id = interner_mod.stringInternerIntern(&in_, y_s);
    var tokens: [12]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[1] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = x_id } };
    tokens[2] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[3] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 10), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 42) } };
    tokens[4] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 12), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[5] = Token{ .kind = TokenKind.kw_extern, .span_start = @intCast(u32, 14), .span_len = @intCast(u16, 6), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[6] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 21), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[7] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 27), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = y_id } };
    tokens[8] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 29), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[9] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 31), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 99) } };
    tokens[10] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 33), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[11] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 35), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src_s: []const u8 = "const x = 42; extern const y = 99;";
    var p = parser_mod.parserInit(tokens[0..], src_s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.module_root)));
    var count: usize = @intCast(usize, node.payload & 0xFFFF);
    assertEqU32(@intCast(u32, count), @intCast(u32, 2));
}
fn testParseModuleRootEmpty() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var src: []const u8 = "";
    var eof_tok: [1]Token = undefined;
    eof_tok[0] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var p = parser_mod.parserInit(eof_tok[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.module_root)));
}
fn testParseModuleRootVarDecl() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var x_s: []const u8 = "x";
    var x_id = interner_mod.stringInternerIntern(&in_, x_s);
    var tokens: [6]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[1] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = x_id } };
    tokens[2] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[3] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 10), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 42) } };
    tokens[4] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 12), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[5] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 13), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "const x = 42;    ";
    var p = parser_mod.parserInit(tokens[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.module_root)));
}
fn testParseQualifiedImport() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var imp_s: []const u8 = "import";
    var path_s: []const u8 = "foo.zig";
    var name_s: []const u8 = "SomeType";
    var import_id = interner_mod.stringInternerIntern(&in_, imp_s);
    var path_id = interner_mod.stringInternerIntern(&in_, path_s);
    var name_id = interner_mod.stringInternerIntern(&in_, name_s);
    var tokens: [7]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.builtin_identifier, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 7), .value = TokenValue{ .string_id = import_id } };
    tokens[1] = Token{ .kind = TokenKind.lparen, .span_start = @intCast(u32, 7), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[2] = Token{ .kind = TokenKind.string_literal, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 9), .value = TokenValue{ .string_id = path_id } };
    tokens[3] = Token{ .kind = TokenKind.rparen, .span_start = @intCast(u32, 17), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[4] = Token{ .kind = TokenKind.dot, .span_start = @intCast(u32, 18), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[5] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 19), .span_len = @intCast(u16, 8), .value = TokenValue{ .string_id = name_id } };
    tokens[6] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 27), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "@import(\"foo.zig\").SomeType";
    var p = parser_mod.parserInit(tokens[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseExprPrec(&p, Prec.assignment) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.field_access)));
    var imp_node = store.nodes.items[node.child_0];
    assertEqU32(@intCast(u32, @enumToInt(imp_node.kind)), @intCast(u32, @enumToInt(AstKind.import_expr)));
    assertEqU32(imp_node.payload, path_id);
    assertEqU32(node.payload, name_id);
}
fn lexAndKind(src: []const u8) u32 {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(src, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseExprPrec(&p, Prec.assignment) catch unreachable;
    var node = store.nodes.items[node_idx];
    return @intCast(u32, @enumToInt(node.kind));
}

fn lexAndKindPrimary(src: []const u8) u32 {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(src, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParsePrimary(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    return @intCast(u32, @enumToInt(node.kind));
}

fn testParseErrorLiteral() void {
    var s: []const u8 = "error.SomeError";
    assertEqU32(lexAndKind(s), @intCast(u32, @enumToInt(AstKind.error_literal)));
}

fn testParseTryExpr() void {
    var s: []const u8 = "try foo()";
    assertEqU32(lexAndKind(s), @intCast(u32, @enumToInt(AstKind.try_expr)));
}

fn testParseIfExpr() void {
    var s: []const u8 = "if (a) b else c";
    assertEqU32(lexAndKind(s), @intCast(u32, @enumToInt(AstKind.if_expr)));
}

fn testParseBlockExpr() void {
    var s: []const u8 = "{ }";
    assertEqU32(lexAndKindPrimary(s), @intCast(u32, @enumToInt(AstKind.block)));
}

fn testParseCatchBlock() void {
    var s: []const u8 = "foo() catch |err| { }";
    assertEqU32(lexAndKind(s), @intCast(u32, @enumToInt(AstKind.catch_expr)));
}

fn testParseOrelseBlock() void {
    var s: []const u8 = "opt orelse 0";
    assertEqU32(lexAndKind(s), @intCast(u32, @enumToInt(AstKind.orelse_expr)));
}

fn testParseArrayLiteral() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var src_s: []const u8 = "[2]u8{ 65, 66 }";
    var tokens: [16]Token = undefined;
    var lex = lexer_mod.lexerInit(src_s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 16) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var p = parser_mod.parserInit(tokens[0..i], src_s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseExprPrec(&p, Prec.assignment) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.array_init)));
    var type_node = store.nodes.items[node.child_0];
    assertEqU32(@intCast(u32, @enumToInt(type_node.kind)), @intCast(u32, @enumToInt(AstKind.array_type)));
}

fn testParseExternFn() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var x_s: []const u8 = "foo";
    var x_id = interner_mod.stringInternerIntern(&in_, x_s);
    var tokens: [7]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.kw_extern, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 6), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[1] = Token{ .kind = TokenKind.kw_fn, .span_start = @intCast(u32, 7), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[2] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 10), .span_len = @intCast(u16, 3), .value = TokenValue{ .string_id = x_id } };
    tokens[3] = Token{ .kind = TokenKind.lparen, .span_start = @intCast(u32, 13), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[4] = Token{ .kind = TokenKind.rparen, .span_start = @intCast(u32, 14), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[5] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 15), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[6] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 16), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "extern fn foo();";
    var p = parser_mod.parserInit(tokens[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.module_root)));
    var count: usize = @intCast(usize, node.payload & 0xFFFF);
    assertEqU32(@intCast(u32, count), @intCast(u32, 1));
}
fn testParseStructInitVarDecl() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var pt_s: []const u8 = "Point";
    var x_s: []const u8 = "x";
    var pt_id = interner_mod.stringInternerIntern(&in_, pt_s);
    var x_id = interner_mod.stringInternerIntern(&in_, x_s);
    var tokens: [12]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[1] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = pt_id } };
    tokens[2] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[3] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 10), .span_len = @intCast(u16, 5), .value = TokenValue{ .string_id = pt_id } };
    tokens[4] = Token{ .kind = TokenKind.lbrace, .span_start = @intCast(u32, 15), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[5] = Token{ .kind = TokenKind.dot, .span_start = @intCast(u32, 17), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[6] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 18), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = x_id } };
    tokens[7] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 20), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[8] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 22), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 1) } };
    tokens[9] = Token{ .kind = TokenKind.rbrace, .span_start = @intCast(u32, 23), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[10] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 24), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[11] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 25), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "const p = Point{ .x = 1 }";
    var p = parser_mod.parserInit(tokens[0..12], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.module_root)));
    var children = ast_mod.astStoreGetExtraChildren(&store, node.payload);
    assertEqU32(@intCast(u32, children.len), @intCast(u32, 1));
    var decl = store.nodes.items[children[0]];
    assertEqU32(@intCast(u32, @enumToInt(decl.kind)), @intCast(u32, @enumToInt(AstKind.var_decl)));
    var init_node = store.nodes.items[decl.child_1];
    assertEqU32(@intCast(u32, @enumToInt(init_node.kind)), @intCast(u32, @enumToInt(AstKind.struct_init)));
}
fn testParseAnonStructInit() void {
    var s: []const u8 = ".{ .x = 1 }";
    var kind = lexAndKind(s);
    assertEqU32(kind, @intCast(u32, @enumToInt(AstKind.struct_init)));
}
fn testParsePositionalTuple() void {
    var s: []const u8 = ".{ 1, 2, 3 }";
    var kind = lexAndKind(s);
    assertEqU32(kind, @intCast(u32, @enumToInt(AstKind.tuple_literal)));
}
fn testParseEnumTypeAsExpr() void {
    var s: []const u8 = "enum { A, B }";
    var kind = lexAndKind(s);
    assertEqU32(kind, @intCast(u32, @enumToInt(AstKind.enum_decl)));
}
fn testParseLabeledBreak() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var label_s: []const u8 = "loop";
    var label_id = interner_mod.stringInternerIntern(&in_, label_s);
    var tokens: [4]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.kw_break, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[1] = Token{ .kind = TokenKind.colon, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[2] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 7), .span_len = @intCast(u16, 4), .value = TokenValue{ .string_id = label_id } };
    tokens[3] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 11), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "break :loop;";
    var p = parser_mod.parserInit(tokens[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseStatement(&p) catch unreachable;
    assertEqU32(@intCast(u32, @enumToInt(store.nodes.items[node_idx].kind)), @intCast(u32, @enumToInt(AstKind.break_stmt)));
    assertEqU32(store.nodes.items[node_idx].payload, label_id);
}

fn testGapB_IfExprBody() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "if (true) dx = 1 else dx = 2;";
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseStatement(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.if_stmt)));
    var cond_kind = @intCast(u32, @enumToInt(store.nodes.items[node.child_0].kind));
    assertEqU32(cond_kind, @intCast(u32, @enumToInt(AstKind.bool_literal)));
    var then_kind = @intCast(u32, @enumToInt(store.nodes.items[node.child_1].kind));
    assertEqU32(then_kind, @intCast(u32, @enumToInt(AstKind.assign)));
    var else_kind = @intCast(u32, @enumToInt(store.nodes.items[node.child_2].kind));
    assertEqU32(else_kind, @intCast(u32, @enumToInt(AstKind.assign)));
}

fn testGapC_ReturnExpr() void {
    var s: []const u8 = "return 42";
    var kind = lexAndKind(s);
    assertEqU32(kind, @intCast(u32, @enumToInt(AstKind.return_stmt)));
}

fn testGapC_BreakExpr() void {
    var s: []const u8 = "break :loop";
    var kind = lexAndKind(s);
    assertEqU32(kind, @intCast(u32, @enumToInt(AstKind.break_stmt)));
}

fn testGapC_SwitchBreak() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "switch (x) { 1 => break :loop, else => {} }";
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseExprPrec(&p, parser_mod.Prec.assignment) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.switch_expr)));
}

fn testGapB_IfExprBody_Chain() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "if (a) b = 1 else if (c) d = 2 else e = 3;";
    var tokens: [48]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 48) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseStatement(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.if_stmt)));
    var then_kind = @intCast(u32, @enumToInt(store.nodes.items[node.child_1].kind));
    assertEqU32(then_kind, @intCast(u32, @enumToInt(AstKind.assign)));
    var else_kind = @intCast(u32, @enumToInt(store.nodes.items[node.child_2].kind));
    assertEqU32(else_kind, @intCast(u32, @enumToInt(AstKind.if_stmt)));
}

fn testGapC_ReturnError() void {
    var s: []const u8 = "return error.Foo";
    var kind = lexAndKind(s);
    assertEqU32(kind, @intCast(u32, @enumToInt(AstKind.return_stmt)));
}

fn testForRange() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "for (1..13) |m| {}";
    var tokens: [16]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 16) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseStatement(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.for_stmt)));
    var pat_kind = @intCast(u32, @enumToInt(store.nodes.items[node.child_0].kind));
    assertEqU32(pat_kind, @intCast(u32, @enumToInt(AstKind.range_exclusive)));
}

fn testDiscardStmt() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "_ = expr;";
    var tokens: [8]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 8) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseStatement(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.assign)));
}

fn testSwitchUnderscoreCapture() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "switch (x) { .Foo => |_| 0, else => 0 }";
    var tokens: [32]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 32) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseExprPrec(&p, parser_mod.Prec.assignment) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.switch_expr)));
}

fn testForUnderscoreCapture() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var s: []const u8 = "for (items) |_| {}";
    var tokens: [16]Token = undefined;
    var lex = lexer_mod.lexerInit(s, @intCast(u32, 0), &in_, &d, &a);
    var i: usize = 0;
    while (i < 16) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(tokens[0..i], s, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParseStatement(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.for_stmt)));
}

fn testLabeledBlockExpr() void {
    var buf: [4096]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var blk_s: []const u8 = "blk";
    var blk_id = interner_mod.stringInternerIntern(&in_, blk_s);
    var tokens: [5]Token = undefined;
    tokens[0] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 3), .value = TokenValue{ .string_id = blk_id } };
    tokens[1] = Token{ .kind = TokenKind.colon, .span_start = @intCast(u32, 3), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[2] = Token{ .kind = TokenKind.lbrace, .span_start = @intCast(u32, 5), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[3] = Token{ .kind = TokenKind.rbrace, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tokens[4] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 7), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src: []const u8 = "blk:{ }";
    var p = parser_mod.parserInit(tokens[0..], src, &store, &in_, &d, &a);
    var node_idx = parser_mod.parserParsePrimary(&p) catch unreachable;
    var node = store.nodes.items[node_idx];
    assertEqU32(@intCast(u32, @enumToInt(node.kind)), @intCast(u32, @enumToInt(AstKind.labeled_stmt)));
}
