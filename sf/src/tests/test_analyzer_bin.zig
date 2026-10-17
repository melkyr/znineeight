const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const type_mod = @import("../type_registry.zig");
const TypeRegistry = type_mod.TypeRegistry;
const ast_mod = @import("../ast.zig");
const AstStore = ast_mod.AstStore;
const AstKind = ast_mod.AstKind;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const az_mod = @import("../analyzer.zig");
const AnalyzerContext = az_mod.AnalyzerContext;
const smap_mod = @import("../state_map.zig");
const sym_mod = @import("../symbol_table.zig");
const SymbolTable = sym_mod.SymbolTable;
const pal = @import("../pal.zig");
const helpers = @import("test_analyzer_helpers.zig");
const Token = @import("../token.zig").Token;
const TokenKind = @import("../token.zig").TokenKind;
const token_mod = @import("../token.zig");
const lexer_mod = @import("../lexer.zig");
const parser_mod = @import("../parser.zig");

fn testSignatureVoidParam() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var type_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, type_mod.TYPE_VOID, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var param_node = ast_mod.astStoreAddNode(&store, AstKind.param_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), type_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var param_buf: [1]u32 = undefined;
    param_buf[0] = param_node;
    var param_payload = ast_mod.astStoreAddExtraChildren(&store, param_buf[0..1]);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, ast_mod.astStoreExtraRangeAt(&store, param_payload) >> @intCast(u64, 32)), .params_count = @intCast(u16, 1), .call_conv = @intCast(u8, 0), .return_type_node = @intCast(u32, 0) };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    az_mod.analyzeSignature(&ac, fn_node);
    helpers.ok("testSignatureVoidParam");
}

fn testSignatureLargeReturn() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var type_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, type_mod.TYPE_U8, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, 0), .params_count = @intCast(u16, 0), .call_conv = @intCast(u8, 0), .return_type_node = type_node };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    az_mod.analyzeSignature(&ac, fn_node);
    helpers.ok("testSignatureLargeReturn");
}

fn testSignatureIncompleteType() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var fs: []const u8 = "Foo";
    var fnid = interner_mod.stringInternerIntern(&interner, fs);
    var ftid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), fnid, type_mod.TypeKind.struct_type);
    _ = ftid;
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var type_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, fnid, @intCast(u32, 0), @intCast(u32, 0));
    var param_node = ast_mod.astStoreAddNode(&store, AstKind.param_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), type_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var param_buf: [1]u32 = undefined;
    param_buf[0] = param_node;
    var param_payload = ast_mod.astStoreAddExtraChildren(&store, param_buf[0..1]);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, ast_mod.astStoreExtraRangeAt(&store, param_payload) >> @intCast(u64, 32)), .params_count = @intCast(u16, 1), .call_conv = @intCast(u8, 0), .return_type_node = @intCast(u32, 0) };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    az_mod.analyzeSignature(&ac, fn_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureIncompleteType expected diagnostic\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureIncompleteType");
}

fn testSignatureAnyType() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var as: []const u8 = "anytype";
    var anid = interner_mod.stringInternerIntern(&interner, as);
    var type_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, anid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, type_node, @intCast(u32, 0));
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureAnyType expected diagnostic\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureAnyType");
}

fn testClassifyNullExpr() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var result = az_mod.classifyExpr(&ac, &st, node);
    if (result != @enumToInt(az_mod.PtrState.is_null)) {
        var fmsg: []const u8 = "testClassifyNullExpr: expected is_null\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyNullExpr");
}

fn testClassifyAddrOf() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var result = az_mod.classifyExpr(&ac, &st, node);
    if (result != @enumToInt(az_mod.PtrState.safe)) {
        var fmsg: []const u8 = "testClassifyAddrOf: expected safe\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyAddrOf");
}

fn testClassifyIdentFromState() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    smap_mod.stateMapSet(&st, @intCast(u32, 42), @enumToInt(az_mod.PtrState.safe));
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, @intCast(u32, 42), @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var result = az_mod.classifyExpr(&ac, &st, id_node);
    if (result != @enumToInt(az_mod.PtrState.safe)) {
        var fmsg: []const u8 = "testClassifyIdentFromState: expected safe\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyIdentFromState");
}

fn testNullVarDeclNull() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var null_node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var st = smap_mod.stateMapInit(&arena);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var vd_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), null_node, @intCast(u32, 0), nid);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    az_mod.handleNullVarDecl(&ac, &st, vd_node);
    var opt = smap_mod.stateMapGet(&st, nid);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.is_null)) {
            var fmsg: []const u8 = "testNullVarDeclNull: expected is_null\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullVarDeclNull: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullVarDeclNull");
}

fn testNullVarDeclNoInit() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var vd_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    az_mod.handleNullVarDecl(&ac, &st, vd_node);
    var opt = smap_mod.stateMapGet(&st, nid);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.uninit)) {
            var fmsg: []const u8 = "testNullVarDeclNoInit: expected uninit\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullVarDeclNoInit: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullVarDeclNoInit");
}

fn testNullAssignNull() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var null_node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
     var as_node = ast_mod.astStoreAddNode(&store, AstKind.plain_assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
     var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    az_mod.handleNullAssign(&ac, &st, as_node);
    var opt = smap_mod.stateMapGet(&st, nid);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.is_null)) {
            var fmsg: []const u8 = "testNullAssignNull: expected is_null\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullAssignNull: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullAssignNull");
}

fn testNullGuardCmpNe() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var null_node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var cmp = ast_mod.astStoreAddNode(&store, AstKind.cmp_ne, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
    var parent = smap_mod.stateMapInit(&arena);
    var then_state = smap_mod.stateMapFork(&parent, &arena);
    var else_state = smap_mod.stateMapFork(&parent, &arena);
    az_mod.applyNullGuardRefinement(&store, cmp, then_state, else_state);
    var t_opt = smap_mod.stateMapGet(then_state, nid);
    if (t_opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.safe)) {
            var fmsg: []const u8 = "testNullGuardCmpNe: then expected safe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardCmpNe: then name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var e_opt = smap_mod.stateMapGet(else_state, nid);
    if (e_opt) |v2| {
        if (v2 != @enumToInt(az_mod.PtrState.is_null)) {
            var fmsg: []const u8 = "testNullGuardCmpNe: else expected is_null\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardCmpNe: else name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullGuardCmpNe");
}

fn testNullGuardCmpEq() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var null_node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var cmp = ast_mod.astStoreAddNode(&store, AstKind.cmp_eq, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
    var parent = smap_mod.stateMapInit(&arena);
    var then_state = smap_mod.stateMapFork(&parent, &arena);
    var else_state = smap_mod.stateMapFork(&parent, &arena);
    az_mod.applyNullGuardRefinement(&store, cmp, then_state, else_state);
    var t_opt = smap_mod.stateMapGet(then_state, nid);
    if (t_opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.is_null)) {
            var fmsg: []const u8 = "testNullGuardCmpEq: then expected is_null\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardCmpEq: then name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var e_opt = smap_mod.stateMapGet(else_state, nid);
    if (e_opt) |v2| {
        if (v2 != @enumToInt(az_mod.PtrState.safe)) {
            var fmsg: []const u8 = "testNullGuardCmpEq: else expected safe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardCmpEq: else name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullGuardCmpEq");
}

fn testNullGuardBoolNot() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var null_node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var eq_node = ast_mod.astStoreAddNode(&store, AstKind.cmp_eq, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
    var not_node = ast_mod.astStoreAddNode(&store, AstKind.bool_not, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), eq_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var parent = smap_mod.stateMapInit(&arena);
    var then_state = smap_mod.stateMapFork(&parent, &arena);
    var else_state = smap_mod.stateMapFork(&parent, &arena);
    az_mod.applyNullGuardRefinement(&store, not_node, then_state, else_state);
    var t_opt = smap_mod.stateMapGet(then_state, nid);
    if (t_opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.safe)) {
            var fmsg: []const u8 = "testNullGuardBoolNot: then expected safe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardBoolNot: then name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var e_opt = smap_mod.stateMapGet(else_state, nid);
    if (e_opt) |v2| {
        if (v2 != @enumToInt(az_mod.PtrState.is_null)) {
            var fmsg: []const u8 = "testNullGuardBoolNot: else expected is_null\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardBoolNot: else name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullGuardBoolNot");
}

fn testNullGuardIdentExpr() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var parent = smap_mod.stateMapInit(&arena);
    var then_state = smap_mod.stateMapFork(&parent, &arena);
    var else_state = smap_mod.stateMapFork(&parent, &arena);
    az_mod.applyNullGuardRefinement(&store, id_node, then_state, else_state);
    var t_opt = smap_mod.stateMapGet(then_state, nid);
    if (t_opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.safe)) {
            var fmsg: []const u8 = "testNullGuardIdentExpr: then expected safe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardIdentExpr: then name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var e_opt = smap_mod.stateMapGet(else_state, nid);
    if (e_opt) |v2| {
        if (v2 != @enumToInt(az_mod.PtrState.is_null)) {
            var fmsg: []const u8 = "testNullGuardIdentExpr: else expected is_null\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testNullGuardIdentExpr: else name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testNullGuardIdentExpr");
}

fn testDerefIsNull() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    smap_mod.stateMapSet(&st, @intCast(u32, 99), @enumToInt(az_mod.PtrState.is_null));
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, @intCast(u32, 99), @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 10));
    var deref_node = ast_mod.astStoreAddNode(&store, AstKind.deref, @intCast(u8, 0), @intCast(u32, 5), @intCast(u32, 15), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    az_mod.analyzeExpr(&ac, &st, deref_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testDerefIsNull: expected error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testDerefIsNull");
}

fn testIfCaptureRefinement() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "val";
    var cap_id = interner_mod.stringInternerIntern(&interner, ns);
    var parent = smap_mod.stateMapInit(&arena);
    var then_state = smap_mod.stateMapFork(&parent, &arena);
    var else_state = smap_mod.stateMapFork(&parent, &arena);
    smap_mod.stateMapSet(then_state, cap_id, @enumToInt(az_mod.PtrState.safe));
    var opt = smap_mod.stateMapGet(then_state, cap_id);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.safe)) {
            var fmsg: []const u8 = "testIfCaptureRefinement: expected safe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testIfCaptureRefinement: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    smap_mod.stateMapMergeStates(&parent, then_state, else_state, @enumToInt(az_mod.PtrState.maybe));
    var opt2 = smap_mod.stateMapGet(&parent, cap_id);
    if (opt2) |_| {
        var fmsg: []const u8 = "testIfCaptureRefinement: capture leaked to parent\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testIfCaptureRefinement");
}

fn testWhileCaptureRefinement() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "val";
    var cap_id = interner_mod.stringInternerIntern(&interner, ns);
    var parent = smap_mod.stateMapInit(&arena);
    var body_state = smap_mod.stateMapFork(&parent, &arena);
    smap_mod.stateMapSet(body_state, cap_id, @enumToInt(az_mod.PtrState.safe));
    var opt = smap_mod.stateMapGet(body_state, cap_id);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.safe)) {
            var fmsg: []const u8 = "testWhileCaptureRefinement: expected safe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testWhileCaptureRefinement: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    smap_mod.stateMapMergeStates(&parent, &parent, body_state, @enumToInt(az_mod.PtrState.maybe));
    var opt2 = smap_mod.stateMapGet(&parent, cap_id);
    if (opt2) |_| {
        var fmsg: []const u8 = "testWhileCaptureRefinement: capture leaked to parent\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testWhileCaptureRefinement");
}

fn testBranchMergeDiff() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var parent = smap_mod.stateMapInit(&arena);
    var then_state = smap_mod.stateMapFork(&parent, &arena);
    var else_state = smap_mod.stateMapFork(&parent, &arena);
    smap_mod.stateMapSet(then_state, nid, @enumToInt(az_mod.PtrState.safe));
    smap_mod.stateMapSet(else_state, nid, @enumToInt(az_mod.PtrState.is_null));
    smap_mod.stateMapMergeStates(&parent, then_state, else_state, @enumToInt(az_mod.PtrState.maybe));
    var opt = smap_mod.stateMapGet(&parent, nid);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.PtrState.maybe)) {
            var fmsg: []const u8 = "testBranchMergeDiff: expected maybe\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testBranchMergeDiff: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testBranchMergeDiff");
}

fn testClassifyAddrLocal() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ns: []const u8 = "x";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var local_sym = sym_mod.Symbol{ .name_id = nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.local, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, local_sym);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var result = az_mod.classifyProvenance(&ac, &st, addr_node);
    var pl: u8 = @intCast(u8, @enumToInt(az_mod.Provenance.local));
    if (result != pl) {
        var fmsg: []const u8 = "testClassifyAddrLocal: expected local\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyAddrLocal");
}

fn testClassifyAddrParam() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ns: []const u8 = "param";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var param_sym = sym_mod.Symbol{ .name_id = nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.param, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, param_sym);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var result = az_mod.classifyProvenance(&ac, &st, addr_node);
    var pa: u8 = @intCast(u8, @enumToInt(az_mod.Provenance.param_addr));
    if (result != pa) {
        var fmsg: []const u8 = "testClassifyAddrParam: expected param_addr\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyAddrParam");
}

fn testClassifyFnCall() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var result = az_mod.classifyProvenance(&ac, &st, fn_node);
    var hp: u8 = @intCast(u8, @enumToInt(az_mod.Provenance.heap));
    if (result != hp) {
        var fmsg: []const u8 = "testClassifyFnCall: expected heap\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyFnCall");
}

fn testClassifyIdent() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    smap_mod.stateMapSet(&st, @intCast(u32, 77), @intCast(u8, @enumToInt(az_mod.Provenance.param)));
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, @intCast(u32, 77), @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var result = az_mod.classifyProvenance(&ac, &st, id_node);
    var pm: u8 = @intCast(u8, @enumToInt(az_mod.Provenance.param));
    if (result != pm) {
        var fmsg: []const u8 = "testClassifyIdent: expected param\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testClassifyIdent");
}

fn testReturnAddrLocal() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ns: []const u8 = "x";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var local_sym = sym_mod.Symbol{ .name_id = nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.local, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, local_sym);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ret_node = ast_mod.astStoreAddNode(&store, AstKind.return_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), addr_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    az_mod.checkReturnProvenance(&ac, &st, addr_node, ret_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testReturnAddrLocal: expected error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_test_ral: []const u8 = "testReturnAddrLocal";
    helpers.ok(ok_test_ral);
}

fn testReturnAddrParam() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ns: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var param_sym = sym_mod.Symbol{ .name_id = nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.param, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, param_sym);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ret_node = ast_mod.astStoreAddNode(&store, AstKind.return_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), addr_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    az_mod.checkReturnProvenance(&ac, &st, addr_node, ret_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testReturnAddrParam: expected error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok1: []const u8 = "testReturnAddrParam";
    helpers.ok(ok1);
}

fn testReturnPtrViaLocal() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ns: []const u8 = "x";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var local_sym = sym_mod.Symbol{ .name_id = nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.local, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, local_sym);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var pn: []const u8 = "p";
    var pid = interner_mod.stringInternerIntern(&interner, pn);
    var p_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, pid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    smap_mod.stateMapSet(&st, pid, @enumToInt(az_mod.Provenance.local));
    var ret_node = ast_mod.astStoreAddNode(&store, AstKind.return_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), p_id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    _ = addr_node;
    az_mod.checkReturnProvenance(&ac, &st, p_id_node, ret_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testReturnPtrViaLocal: expected warning\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok2: []const u8 = "testReturnPtrViaLocal";
    helpers.ok(ok2);
}

fn testReturnSliceLocal() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var st = smap_mod.stateMapInit(&arena);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ns: []const u8 = "arr";
    var nid = interner_mod.stringInternerIntern(&interner, ns);
    var local_sym = sym_mod.Symbol{ .name_id = nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.local, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, local_sym);
    var arr_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var slice_node = ast_mod.astStoreAddNode(&store, AstKind.slice_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), arr_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.Provenance.local));
    var ret_node = ast_mod.astStoreAddNode(&store, AstKind.return_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), slice_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    az_mod.checkReturnProvenance(&ac, &st, slice_node, ret_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testReturnSliceLocal: expected warning\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var okrsl: []const u8 = "testReturnSliceLocal";
    helpers.ok(okrsl);
}

fn testAllocStateEnumValues() void {
    if (@enumToInt(az_mod.AllocState.untracked) != @intCast(u8, 0)) { var msg: []const u8 = "testAllocStateEnumValues: untracked should be 0\n"; pal.stdout_write(msg); pal.exit(1); }
    if (@enumToInt(az_mod.AllocState.allocated) != @intCast(u8, 1)) { var msg: []const u8 = "testAllocStateEnumValues: allocated should be 1\n"; pal.stdout_write(msg); pal.exit(1); }
    if (@enumToInt(az_mod.AllocState.freed) != @intCast(u8, 2)) { var msg: []const u8 = "testAllocStateEnumValues: freed should be 2\n"; pal.stdout_write(msg); pal.exit(1); }
    if (@enumToInt(az_mod.AllocState.returned_val) != @intCast(u8, 3)) { var msg: []const u8 = "testAllocStateEnumValues: returned_val should be 3\n"; pal.stdout_write(msg); pal.exit(1); }
    if (@enumToInt(az_mod.AllocState.transferred) != @intCast(u8, 4)) { var msg: []const u8 = "testAllocStateEnumValues: transferred should be 4\n"; pal.stdout_write(msg); pal.exit(1); }
    if (@enumToInt(az_mod.AllocState.unknown) != @intCast(u8, 5)) { var msg: []const u8 = "testAllocStateEnumValues: unknown should be 5\n"; pal.stdout_write(msg); pal.exit(1); }
    var okaev: []const u8 = "testAllocStateEnumValues";
    helpers.ok(okaev);
}

fn testIsAllocCall() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var sa: []const u8 = "sandAlloc";
    var sand_nid = interner_mod.stringInternerIntern(&interner, sa);
    var callee = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, sand_nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var alloc_call = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    if (!az_mod.isAllocCall(&ac, alloc_call)) {
        var msg: []const u8 = "testIsAllocCall: expected true for sandAlloc call\n";
        pal.stdout_write(msg); pal.exit(1);
    }
    var try_alloc = ast_mod.astStoreAddNode(&store, AstKind.try_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), alloc_call, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    if (!az_mod.isAllocCall(&ac, try_alloc)) {
        var msg: []const u8 = "testIsAllocCall: expected true for try sandAlloc\n";
        pal.stdout_write(msg); pal.exit(1);
    }
    var ofs: []const u8 = "otherFunc";
    var other_nid = interner_mod.stringInternerIntern(&interner, ofs);
    var other_callee = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, other_nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var other_call = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), other_callee, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    if (az_mod.isAllocCall(&ac, other_call)) {
        var msg: []const u8 = "testIsAllocCall: expected false for otherFunc\n";
        pal.stdout_write(msg); pal.exit(1);
    }
    var zero_expr: u32 = 0;
    if (az_mod.isAllocCall(&ac, zero_expr)) {
        var msg: []const u8 = "testIsAllocCall: expected false for zero expr\n";
        pal.stdout_write(msg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testIsAllocCall";
    helpers.ok(ok_msg);
}

fn testIsFreeCall() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);

    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    var free_s: []const u8 = "arena_free";
    var free_nid = interner_mod.stringInternerIntern(&interner, free_s);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, free_nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var ptr_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg0_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, @intCast(u32, 99), @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = arg0_node;
    arg_buf[1] = ptr_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    var result = az_mod.isFreeCall(&ac, call_node);
    if (result) |v| {
        if (v != nid) {
            var msg: []const u8 = "testIsFreeCall: expected nid\n";
            pal.stdout_write(msg); pal.exit(1);
        }
    } else {
        var msg: []const u8 = "testIsFreeCall: expected non-null\n";
        pal.stdout_write(msg); pal.exit(1);
    }

    var other_s: []const u8 = "otherFunc";
    var other_nid = interner_mod.stringInternerIntern(&interner, other_s);
    var other_callee = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, other_nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var other_payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var other_call = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), other_callee, @intCast(u32, 0), @intCast(u32, 0), other_payload);
    var result2 = az_mod.isFreeCall(&ac, other_call);
    if (result2) |v| {
        _ = v;
        var msg: []const u8 = "testIsFreeCall: expected null for non-free\n";
        pal.stdout_write(msg); pal.exit(1);
    }

    var result3 = az_mod.isFreeCall(&ac, @intCast(u32, 0));
    if (result3) |v| {
        _ = v;
        var msg: []const u8 = "testIsFreeCall: expected null for zero\n";
        pal.stdout_write(msg); pal.exit(1);
    }

    var ok2: []const u8 = "testIsFreeCall";
    helpers.ok(ok2);
}

fn testHandleAllocCall() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var sa: []const u8 = "sandAlloc";
    var sa_id = interner_mod.stringInternerIntern(&interner, sa);
    var sa_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, sa_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), sa_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    az_mod.handleAllocCall(&ac, &st, nid, call_node);
    var opt = smap_mod.stateMapGet(&st, nid);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.AllocState.allocated)) {
            var fmsg: []const u8 = "testHandleAllocCall: expected allocated\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testHandleAllocCall: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testHandleAllocCall";
    helpers.ok(ok_msg);
}

fn testHandleFreeCall() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps2: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps2);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var af: []const u8 = "arena_free";
    var af_id = interner_mod.stringInternerIntern(&interner, af);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, af_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var pid_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    arg_buf[1] = pid_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.handleFreeCall(&ac, &st, call_node);
    var opt = smap_mod.stateMapGet(&st, nid);
    if (opt) |v| {
        if (v != @enumToInt(az_mod.AllocState.freed)) {
            var fmsg: []const u8 = "testHandleFreeCall: expected freed\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testHandleFreeCall: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testHandleFreeCall";
    helpers.ok(ok_msg);
}

fn testHandleDoubleFree() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps3: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps3);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.freed));
    var af: []const u8 = "arena_free";
    var af_id = interner_mod.stringInternerIntern(&interner, af);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, af_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var pid_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    arg_buf[1] = pid_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.handleFreeCall(&ac, &st, call_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testHandleDoubleFree: expected error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testHandleDoubleFree";
    helpers.ok(ok_msg);
}

fn testScopeLeakDetected() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    smap_mod.stateMapSet(&st, @intCast(u32, 42), @enumToInt(az_mod.AllocState.allocated));
    smap_mod.stateMapSet(&st, @intCast(u32, 43), @enumToInt(az_mod.AllocState.freed));
    az_mod.checkLeaksOnScopeExit(&ac, &st);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testScopeLeakDetected: expected warning\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testScopeLeakDetected";
    helpers.ok(ok_msg);
}

fn testScopeNoLeakAfterFree() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    smap_mod.stateMapSet(&st, @intCast(u32, 42), @enumToInt(az_mod.AllocState.freed));
    az_mod.checkLeaksOnScopeExit(&ac, &st);
    if (diag.warning_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testScopeNoLeakAfterFree: expected no warning\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testScopeNoLeakAfterFree";
    helpers.ok(ok_msg);
}

fn testCompositeNameId() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var cont: []const u8 = "container";
    var cont_id = interner_mod.stringInternerIntern(&interner, cont);
    var ptrs: []const u8 = "ptr";
    var ptr_id = interner_mod.stringInternerIntern(&interner, ptrs);
    var composite = az_mod.compositeNameId(&interner, cont_id, ptr_id);
    var expected: []const u8 = "container.ptr";
    var expected_id = interner_mod.stringInternerIntern(&interner, expected);
    if (composite != expected_id) {
        var fmsg: []const u8 = "testCompositeNameId: composite ID mismatch\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg2: []const u8 = "testCompositeNameId";
    helpers.ok(ok_msg2);
}

fn testFreeUntracked() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var pn: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, pn);
    var af: []const u8 = "arena_free";
    var af_id = interner_mod.stringInternerIntern(&interner, af);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, af_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    var pid_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    arg_buf[1] = pid_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var free_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 5), @intCast(u32, 15), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.handleFreeCall(&ac, &st, free_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testFreeUntracked: expected WARN_6006 for untracked pointer (spec gap)\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testFreeUntracked";
    helpers.ok(ok_msg);
}

fn testOwnershipNoTransfer() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var pn: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, pn);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var pr_name: []const u8 = "std.debug.print";
    var pr_id = interner_mod.stringInternerIntern(&interner, pr_name);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, pr_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    var pid_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    arg_buf[1] = pid_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 5), @intCast(u32, 15), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.handleOwnershipPass(&ac, &st, call_node);
    var result = smap_mod.stateMapGet(&st, nid);
    if (result) |v| {
        if (v != @enumToInt(az_mod.AllocState.transferred)) {
            var fmsg: []const u8 = "testOwnershipNoTransfer: expected transferred\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    }
    var ok_msg: []const u8 = "testOwnershipNoTransfer";
    helpers.ok(ok_msg);
}

fn testDoubleFreeNested() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var pn: []const u8 = "q";
    var nid = interner_mod.stringInternerIntern(&interner, pn);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.freed));
    var af: []const u8 = "arena_free";
    var af_id = interner_mod.stringInternerIntern(&interner, af);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, af_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    var pid_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    arg_buf[1] = pid_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..2]);
    var free_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 5), @intCast(u32, 15), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.handleFreeCall(&ac, &st, free_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testDoubleFreeNested: expected error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testDoubleFreeNested";
    helpers.ok(ok_msg);
}

fn testAllocAssignLeak() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var sa: []const u8 = "sandAlloc";
    var sa_id = interner_mod.stringInternerIntern(&interner, sa);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, sa_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf2: [2]u32 = undefined;
    arg_buf2[0] = @intCast(u32, 0);
    arg_buf2[1] = @intCast(u32, 0);
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf2[0..2]);
    var alloc_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
     var as_node = ast_mod.astStoreAddNode(&store, AstKind.plain_assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, alloc_node, @intCast(u32, 0), @intCast(u32, 0));
     az_mod.handleAllocAssign(&ac, &st, as_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testAllocAssignLeak: expected warning\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testAllocAssignLeak";
    helpers.ok(ok_msg);
}

fn testAllocAssignNull() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var null_node = ast_mod.astStoreAddNode(&store, AstKind.null_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
     var as_node = ast_mod.astStoreAddNode(&store, AstKind.plain_assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
     az_mod.handleAllocAssign(&ac, &st, as_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testAllocAssignNull: expected warning\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testAllocAssignNull";
    helpers.ok(ok_msg);
}

fn testOwnershipReturn() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    az_mod.handleOwnershipReturn(&ac, &st, id_node);
    var result = smap_mod.stateMapGet(&st, nid);
    if (result) |v| {
        if (v != @enumToInt(az_mod.AllocState.returned_val)) {
            var fmsg: []const u8 = "testOwnershipReturn: expected returned_val\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testOwnershipReturn: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testOwnershipReturn";
    helpers.ok(ok_msg);
}

fn testOwnershipPassArg() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var ptr_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var arg_buf: [1]u32 = undefined;
    arg_buf[0] = ptr_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..1]);
    var callee_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_id_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.handleOwnershipPass(&ac, &st, call_node);
    var result = smap_mod.stateMapGet(&st, nid);
    if (result) |v| {
        if (v != @enumToInt(az_mod.AllocState.transferred)) {
            var fmsg: []const u8 = "testOwnershipPassArg: expected transferred\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testOwnershipPassArg: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testOwnershipPassArg";
    helpers.ok(ok_msg);
}

fn testDeferFree() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var st = smap_mod.stateMapInit(&arena);
    var ps: []const u8 = "p";
    var nid = interner_mod.stringInternerIntern(&interner, ps);
    smap_mod.stateMapSet(&st, nid, @enumToInt(az_mod.AllocState.allocated));
    var af: []const u8 = "arena_free";
    var af_id = interner_mod.stringInternerIntern(&interner, af);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, af_id, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var pid_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, nid, @intCast(u32, 0), @intCast(u32, 0) + @intCast(u32, 0));
    var argb: [2]u32 = undefined;
    argb[0] = @intCast(u32, 0);
    argb[1] = pid_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, argb[0..2]);
    var free_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    az_mod.deferQueueEnsureCapacity(&ac, @intCast(usize, 1));
    ac.defer_queue_items[0] = az_mod.DeferEntry{ .kind = @intCast(u8, 0), .stmt_idx = free_node, .scope_depth = @intCast(u32, 0) };
    ac.defer_queue_len = @intCast(usize, 1);
    az_mod.handleFreeCall(&ac, &st, free_node);
    var result = smap_mod.stateMapGet(&st, nid);
    if (result) |v| {
        if (v != @enumToInt(az_mod.AllocState.freed)) {
            var fmsg: []const u8 = "testDeferFree: expected freed\n";
            pal.stdout_write(fmsg); pal.exit(1);
        }
    } else {
        var fmsg: []const u8 = "testDeferFree: name not found\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testDeferFree";
    helpers.ok(ok_msg);
}

fn testRunAllAnalyzers() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var sym_table = sym_mod.symbolTableInit(&arena);
    var ac: AnalyzerContext = undefined;
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var s_sandAlloc: []const u8 = "sandAlloc";
    var sandAlloc_nid = interner_mod.stringInternerIntern(&interner, s_sandAlloc);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, sandAlloc_nid, @intCast(u32, 0), @intCast(u32, 0));
    var argb: [1]u32 = undefined;
    argb[0] = @intCast(u32, 0);
    var call_payload = ast_mod.astStoreAddExtraChildren(&store, argb[0..1]);
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), call_payload);
    var pname: []const u8 = "p";
    var p_nid = interner_mod.stringInternerIntern(&interner, pname);
    var decl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), call_node, @intCast(u32, 0), p_nid);
    var stmt_buf: [1]u32 = undefined;
    stmt_buf[0] = decl_node;
    var block_payload = ast_mod.astStoreAddExtraChildren(&store, stmt_buf[0..1]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), block_payload);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, 0), .params_count = @intCast(u16, 0), .call_conv = @intCast(u8, 0), .return_type_node = @intCast(u32, 0) };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), body_node, @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    var decl_buf: [1]u32 = undefined;
    decl_buf[0] = fn_node;
    var mr_payload = ast_mod.astStoreAddExtraChildren(&store, decl_buf[0..1]);
    var mr_node = ast_mod.astStoreAddNode(&store, AstKind.module_root, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), mr_payload);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testRunAllAnalyzers: expected warnings (leak detected)\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testRunAllAnalyzers";
    helpers.ok(ok_msg);
}

fn testSignatureFnPtrOptAggregate() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ks: []const u8 = "Key";
    var knid = interner_mod.stringInternerIntern(&interner, ks);
    var ktid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), knid, type_mod.TypeKind.struct_type);
    typereg.types_items[@intCast(usize, ktid)].state = @intCast(u8, 2);
    var key_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, knid, @intCast(u32, 0), @intCast(u32, 0));
    var opt_node = ast_mod.astStoreAddNode(&store, AstKind.optional_type, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), key_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var fnt_node = ast_mod.astStoreAddNode(&store, AstKind.fn_type, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), opt_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var param_node = ast_mod.astStoreAddNode(&store, AstKind.param_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), fnt_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var param_buf: [1]u32 = undefined;
    param_buf[0] = param_node;
    var param_payload = ast_mod.astStoreAddExtraChildren(&store, param_buf[0..1]);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, ast_mod.astStoreExtraRangeAt(&store, param_payload) >> @intCast(u64, 32)), .params_count = @intCast(u16, 1), .call_conv = @intCast(u8, 0), .return_type_node = fnt_node };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    az_mod.analyzeSignature(&ac, fn_node);
    if (diag.error_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureFnPtrOptAggregate: expected 0 errors\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureFnPtrOptAggregate");
}

fn testSignatureFnPtrErrUnionAggregate() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ks: []const u8 = "Key";
    var knid = interner_mod.stringInternerIntern(&interner, ks);
    var ktid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), knid, type_mod.TypeKind.struct_type);
    typereg.types_items[@intCast(usize, ktid)].state = @intCast(u8, 2);
    var key_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, knid, @intCast(u32, 0), @intCast(u32, 0));
    var eu_node = ast_mod.astStoreAddNode(&store, AstKind.error_union_type, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), key_node, @intCast(u32, 0), @intCast(u32, 0));
    var fnt_node = ast_mod.astStoreAddNode(&store, AstKind.fn_type, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), eu_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, 0), .params_count = @intCast(u16, 0), .call_conv = @intCast(u8, 0), .return_type_node = fnt_node };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    az_mod.analyzeSignature(&ac, fn_node);
    if (diag.error_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureFnPtrErrUnionAggregate: expected 0 errors\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureFnPtrErrUnionAggregate");
}

fn testSignatureNestedIncomplete() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var fs: []const u8 = "Foo";
    var fnid = interner_mod.stringInternerIntern(&interner, fs);
    var ftid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), fnid, type_mod.TypeKind.struct_type);
    _ = ftid;
    var foo_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, fnid, @intCast(u32, 0), @intCast(u32, 0));
    var opt_node = ast_mod.astStoreAddNode(&store, AstKind.optional_type, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), foo_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, opt_node, @intCast(u32, 1));
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureNestedIncomplete: expected incomplete-type error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureNestedIncomplete");
}

fn testSignatureArbIntAccepted() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var s7: []const u8 = "i7";
    _ = type_mod.typeRegistryGetOrCreateArbInt(&typereg, s7);
    var n7 = interner_mod.stringInternerIntern(&interner, s7);
    var node7 = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, n7, @intCast(u32, 0), @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, node7, @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, node7, @intCast(u32, 1));
    var s48: []const u8 = "u48";
    var n48 = interner_mod.stringInternerIntern(&interner, s48);
    var node48 = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, n48, @intCast(u32, 0), @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, node48, @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, node48, @intCast(u32, 1));
    if (diag.error_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureArbIntAccepted: expected 0 errors\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureArbIntAccepted");
}

fn testSignaturePackedUnionIncomplete() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ps: []const u8 = "PU";
    var pnid = interner_mod.stringInternerIntern(&interner, ps);
    var ptid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), pnid, type_mod.TypeKind.packed_union_type);
    _ = ptid;
    var pu_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, pnid, @intCast(u32, 0), @intCast(u32, 0));
    az_mod.validateSignatureType(&ac, pu_node, @intCast(u32, 0));
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignaturePackedUnionIncomplete: expected incomplete-type error\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignaturePackedUnionIncomplete");
}

fn testSignatureMemberTypeAccepted() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var ks: []const u8 = "Key";
    var knid = interner_mod.stringInternerIntern(&interner, ks);
    var ktid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), knid, type_mod.TypeKind.struct_type);
    typereg.types_items[@intCast(usize, ktid)].state = @intCast(u8, 2);
    var ms: []const u8 = "m";
    var mnid = interner_mod.stringInternerIntern(&interner, ms);
    var base_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, mnid, @intCast(u32, 0), @intCast(u32, 0));
    var fa_node = ast_mod.astStoreAddNode(&store, AstKind.field_access, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), base_node, @intCast(u32, 0), @intCast(u32, 0), knid);
    az_mod.validateSignatureType(&ac, fa_node, @intCast(u32, 1));
    if (diag.error_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testSignatureMemberTypeAccepted: expected 0 errors\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testSignatureMemberTypeAccepted");
}

fn buildRunModule(store: *AstStore, body_node: u32) u32 {
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u32, 0), .params_count = @intCast(u16, 0), .call_conv = @intCast(u8, 0), .return_type_node = @intCast(u32, 0) };
    var proto_idx = ast_mod.astStoreAddFnProto(store, proto);
    var fn_node = ast_mod.astStoreAddNode(store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), body_node, @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    var decl_buf: [1]u32 = undefined;
    decl_buf[0] = fn_node;
    var mr_payload = ast_mod.astStoreAddExtraChildren(store, decl_buf[0..1]);
    return ast_mod.astStoreAddNode(store, AstKind.module_root, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), mr_payload);
}

fn testCaptureLifetimePropagation() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var xs: []const u8 = "x";
    var x_nid = interner_mod.stringInternerIntern(&interner, xs);
    var local_sym = sym_mod.Symbol{ .name_id = x_nid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.local, .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0), .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0), .file_id = @intCast(u32, 0) };
    _ = sym_mod.symbolTableInsert(&sym_table, local_sym);
    var ten_node = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 10), @intCast(u32, 0), @intCast(u32, 4));
    var xdecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), ten_node, @intCast(u32, 0), x_nid);
    var x_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, x_nid, @intCast(u32, 0), @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), x_id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ops: []const u8 = "op";
    var op_nid = interner_mod.stringInternerIntern(&interner, ops);
    var odecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), addr_node, @intCast(u32, 0), op_nid);
    var ps: []const u8 = "ptr";
    var ptr_nid = interner_mod.stringInternerIntern(&interner, ps);
    var cap_node = ast_mod.astStoreAddNode(&store, AstKind.if_capture, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), ptr_nid);
    var op_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, op_nid, @intCast(u32, 0), @intCast(u32, 0));
    var ptr_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, ptr_nid, @intCast(u32, 0), @intCast(u32, 0));
    var ret_node = ast_mod.astStoreAddNode(&store, AstKind.return_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), ptr_id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var then_buf: [1]u32 = undefined;
    then_buf[0] = ret_node;
    var then_payload = ast_mod.astStoreAddExtraChildren(&store, then_buf[0..1]);
    var then_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), then_payload);
    var if_node = ast_mod.astStoreAddNode(&store, AstKind.if_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), op_id_node, then_node, @intCast(u32, 0), cap_node);
    var body_buf: [3]u32 = undefined;
    body_buf[0] = xdecl_node;
    body_buf[1] = odecl_node;
    body_buf[2] = if_node;
    var body_payload = ast_mod.astStoreAddExtraChildren(&store, body_buf[0..3]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), body_payload);
    var mr_node = buildRunModule(&store, body_node);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.error_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testCaptureLifetimePropagation: expected 0 errors\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg2: []const u8 = "testCaptureLifetimePropagation: expected capture provenance warning (tech-debt 2.1)\n";
        pal.stdout_write(fmsg2); pal.exit(1);
    }
    helpers.ok("testCaptureLifetimePropagation");
}

fn testCaptureNullSafe() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var zs: []const u8 = "z";
    var z_nid = interner_mod.stringInternerIntern(&interner, zs);
    var one_node = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 1), @intCast(u32, 0), @intCast(u32, 4));
    var zdecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), one_node, @intCast(u32, 0), z_nid);
    var z_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, z_nid, @intCast(u32, 0), @intCast(u32, 0));
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), z_id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ps: []const u8 = "p";
    var p_nid = interner_mod.stringInternerIntern(&interner, ps);
    var pdecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), addr_node, @intCast(u32, 0), p_nid);
    var ops: []const u8 = "op";
    var op_nid = interner_mod.stringInternerIntern(&interner, ops);
    var p_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, p_nid, @intCast(u32, 0), @intCast(u32, 0));
    var odecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), p_id_node, @intCast(u32, 0), op_nid);
    var vs: []const u8 = "v";
    var v_nid = interner_mod.stringInternerIntern(&interner, vs);
    var cap_node = ast_mod.astStoreAddNode(&store, AstKind.if_capture, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), v_nid);
    var op_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, op_nid, @intCast(u32, 0), @intCast(u32, 0));
    var v_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, v_nid, @intCast(u32, 0), @intCast(u32, 0));
    var deref_node = ast_mod.astStoreAddNode(&store, AstKind.deref, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), v_id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ws: []const u8 = "w";
    var w_nid = interner_mod.stringInternerIntern(&interner, ws);
    var w_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, w_nid, @intCast(u32, 0), @intCast(u32, 0));
    var asn_node = ast_mod.astStoreAddNode(&store, AstKind.plain_assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), w_id_node, deref_node, @intCast(u32, 0), @intCast(u32, 0));
    var then_buf: [1]u32 = undefined;
    then_buf[0] = asn_node;
    var then_payload = ast_mod.astStoreAddExtraChildren(&store, then_buf[0..1]);
    var then_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), then_payload);
    var if_node = ast_mod.astStoreAddNode(&store, AstKind.if_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), op_id_node, then_node, @intCast(u32, 0), cap_node);
    var body_buf: [4]u32 = undefined;
    body_buf[0] = zdecl_node;
    body_buf[1] = pdecl_node;
    body_buf[2] = odecl_node;
    body_buf[3] = if_node;
    var body_payload = ast_mod.astStoreAddExtraChildren(&store, body_buf[0..4]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), body_payload);
    var mr_node = buildRunModule(&store, body_node);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.error_count != @intCast(usize, 0) or diag.warning_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testCaptureNullSafe: expected clean run (capture is safe)\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testCaptureNullSafe");
}

fn testCaptureDoubleFree() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var as: []const u8 = "sandAlloc";
    var a_nid = interner_mod.stringInternerIntern(&interner, as);
    var callee_a = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, a_nid, @intCast(u32, 0), @intCast(u32, 0));
    var argb: [1]u32 = undefined;
    argb[0] = @intCast(u32, 0);
    var call_payload = ast_mod.astStoreAddExtraChildren(&store, argb[0..1]);
    var alloc_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_a, @intCast(u32, 0), @intCast(u32, 0), call_payload);
    var ops: []const u8 = "op";
    var op_nid = interner_mod.stringInternerIntern(&interner, ops);
    var odecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), alloc_node, @intCast(u32, 0), op_nid);
    var qs: []const u8 = "q";
    var q_nid = interner_mod.stringInternerIntern(&interner, qs);
    var cap_node = ast_mod.astStoreAddNode(&store, AstKind.if_capture, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), q_nid);
    var op_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, op_nid, @intCast(u32, 0), @intCast(u32, 0));
    var fs: []const u8 = "sandFree";
    var f_nid = interner_mod.stringInternerIntern(&interner, fs);
    var q_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, q_nid, @intCast(u32, 0), @intCast(u32, 0));
    var farg_buf: [2]u32 = undefined;
    farg_buf[0] = @intCast(u32, 0);
    farg_buf[1] = q_id_node;
    var f_payload = ast_mod.astStoreAddExtraChildren(&store, farg_buf[0..2]);
    var callee_f = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, f_nid, @intCast(u32, 0), @intCast(u32, 0));
    var free_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_f, @intCast(u32, 0), @intCast(u32, 0), f_payload);
    var then_buf: [2]u32 = undefined;
    then_buf[0] = free_node;
    then_buf[1] = free_node;
    var then_payload = ast_mod.astStoreAddExtraChildren(&store, then_buf[0..2]);
    var then_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), then_payload);
    var if_node = ast_mod.astStoreAddNode(&store, AstKind.if_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), op_id_node, then_node, @intCast(u32, 0), cap_node);
    var body_buf: [2]u32 = undefined;
    body_buf[0] = odecl_node;
    body_buf[1] = if_node;
    var body_payload = ast_mod.astStoreAddExtraChildren(&store, body_buf[0..2]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), body_payload);
    var mr_node = buildRunModule(&store, body_node);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.error_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testCaptureDoubleFree: expected double-free error through capture\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testCaptureDoubleFree");
}

fn testDeadArmSkipped() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var ac: AnalyzerContext = undefined;
    var sym_table = sym_mod.symbolTableInit(&arena);
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var as: []const u8 = "sandAlloc";
    var a_nid = interner_mod.stringInternerIntern(&interner, as);
    var callee_a = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, a_nid, @intCast(u32, 0), @intCast(u32, 0));
    var argb: [1]u32 = undefined;
    argb[0] = @intCast(u32, 0);
    var call_payload = ast_mod.astStoreAddExtraChildren(&store, argb[0..1]);
    var alloc_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_a, @intCast(u32, 0), @intCast(u32, 0), call_payload);
    var ps: []const u8 = "p";
    var p_nid = interner_mod.stringInternerIntern(&interner, ps);
    var pdecl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), alloc_node, @intCast(u32, 0), p_nid);
    var fs: []const u8 = "sandFree";
    var f_nid = interner_mod.stringInternerIntern(&interner, fs);
    var p_id_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, p_nid, @intCast(u32, 0), @intCast(u32, 0));
    var farg_buf: [2]u32 = undefined;
    farg_buf[0] = @intCast(u32, 0);
    farg_buf[1] = p_id_node;
    var f_payload = ast_mod.astStoreAddExtraChildren(&store, farg_buf[0..2]);
    var callee_f = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, f_nid, @intCast(u32, 0), @intCast(u32, 0));
    var free_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_f, @intCast(u32, 0), @intCast(u32, 0), f_payload);
    var false_node = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var then_buf: [2]u32 = undefined;
    then_buf[0] = free_node;
    then_buf[1] = free_node;
    var then_payload = ast_mod.astStoreAddExtraChildren(&store, then_buf[0..2]);
    var then_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), then_payload);
    var if_node = ast_mod.astStoreAddNode(&store, AstKind.if_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), false_node, then_node, @intCast(u32, 0), @intCast(u32, 0));
    var body_buf: [3]u32 = undefined;
    body_buf[0] = pdecl_node;
    body_buf[1] = if_node;
    body_buf[2] = free_node;
    var body_payload = ast_mod.astStoreAddExtraChildren(&store, body_buf[0..3]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), body_payload);
    var mr_node = buildRunModule(&store, body_node);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.error_count != @intCast(usize, 0) or diag.warning_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testDeadArmSkipped: expected clean run (dead arm not analyzed)\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    helpers.ok("testDeadArmSkipped");
}

var fx_perm_buf: [2097152]u8 = undefined;
var fx_scratch_buf: [262144]u8 = undefined;
var fx_type_buf: [131072]u8 = undefined;
var fx_tok_buf: [32768]Token = undefined;

// T5 fixture runner for tests/analyzers/**: lex + parse each fixture and run
// runAllAnalyzers over the parsed module. err_spec/warn_spec: 0 = must be
// zero, -1 = don't care, N > 0 = must be >= N. Run the binary from the repo
// root (fixture paths are repo-relative).
fn testFixture(path: []const u8, name: []const u8, err_spec: i32, warn_spec: i32) void {
    var perm = alloc_mod.sandInit(fx_perm_buf[0..]);
    var scratch = alloc_mod.sandInit(fx_scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var content = pal.readFile(path, &scratch) orelse {
        var emsg: []const u8 = "FAIL: could not read fixture: ";
        pal.stderr_write(emsg);
        pal.stderr_write(path);
        var nl: []const u8 = "\n";
        pal.stderr_write(nl);
        pal.exit(1);
        return;
    };
    var tok_len: usize = 0;
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), &interner, &diag, &scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        fx_tok_buf[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&perm);
    var p = parser_mod.parserInit(fx_tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch {
        var emsg: []const u8 = "FAIL: fixture parse error: ";
        pal.stderr_write(emsg);
        pal.stderr_write(name);
        var nl: []const u8 = "\n";
        pal.stderr_write(nl);
        pal.exit(1);
        return;
    };
    alloc_mod.sandReset(&scratch);
    var type_db = alloc_mod.sandInit(fx_type_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var sym_table = sym_mod.symbolTableInit(&scratch);
    var ac = AnalyzerContext{
        .store = &store, .registry = &typereg, .interner = &interner,
        .diag = &diag, .symbols = &sym_table, .alloc = &scratch,
        .current_fn_name = @intCast(u32, 0),
        .defer_queue_items = undefined, .defer_queue_len = @intCast(usize, 0),
        .defer_queue_cap = @intCast(usize, 0), .defer_queue_alloc = &scratch,
        .current_depth = @intCast(u32, 0),
        .null_analysis_mode = @intCast(u8, 0),
        .skip_null_check = @intCast(u8, 0),
        .skip_lifetime_check = @intCast(u8, 0),
        .skip_doublefree_check = @intCast(u8, 0),
        .warn_all = @intCast(u8, 0),
        .on_stmt_cb = az_mod.onNullStmt,
        .in_defer_exec = @intCast(u8, 0),
        .lifetime_analysis_mode = @intCast(u8, 0),
        .doublefree_analysis_mode = @intCast(u8, 0),
        .source_file_id = @intCast(u32, 0),
    };
    az_mod.runAllAnalyzers(&ac, ast_root);
    if (err_spec == @intCast(i32, 0) and diag.error_count != @intCast(usize, 0)) {
        pal.stderr_write(name);
        helpers.fail(" fixture: expected 0 errors");
    }
    if (err_spec > @intCast(i32, 0) and diag.error_count < @intCast(usize, err_spec)) {
        pal.stderr_write(name);
        helpers.fail(" fixture: expected errors");
    }
    if (warn_spec == @intCast(i32, 0) and diag.warning_count != @intCast(usize, 0)) {
        pal.stderr_write(name);
        helpers.fail(" fixture: expected 0 warnings");
    }
    if (warn_spec > @intCast(i32, 0) and diag.warning_count < @intCast(usize, warn_spec)) {
        pal.stderr_write(name);
        helpers.fail(" fixture: expected warnings");
    }
    helpers.ok(name);
}

pub fn main() void {
    pal.initArgs(0, undefined);
    testSignatureVoidParam();
    testSignatureLargeReturn();
    testSignatureIncompleteType();
    testSignatureAnyType();
    testClassifyNullExpr();
    testClassifyAddrOf();
    testClassifyIdentFromState();
    testNullVarDeclNull();
    testNullVarDeclNoInit();
    testNullAssignNull();
    testNullGuardCmpNe();
    testNullGuardCmpEq();
    testNullGuardBoolNot();
    testNullGuardIdentExpr();
    testDerefIsNull();
    testIfCaptureRefinement();
    testWhileCaptureRefinement();
    testBranchMergeDiff();
    testClassifyAddrLocal();
    testClassifyAddrParam();
    testClassifyFnCall();
    testClassifyIdent();
    testReturnAddrLocal();
    testReturnAddrParam();
    testReturnPtrViaLocal();
    testReturnSliceLocal();
    testAllocStateEnumValues();
    testIsAllocCall();
    testIsFreeCall();
    testHandleAllocCall();
    testHandleFreeCall();
    testHandleDoubleFree();
    testScopeLeakDetected();
    testScopeNoLeakAfterFree();
    testAllocAssignLeak();
    testAllocAssignNull();
    testOwnershipReturn();
    testOwnershipPassArg();
    testDeferFree();
    testCompositeNameId();
    testFreeUntracked();
    testOwnershipNoTransfer();
    testDoubleFreeNested();
    testRunAllAnalyzers();
    testSignatureFnPtrOptAggregate();
    testSignatureFnPtrErrUnionAggregate();
    testSignatureNestedIncomplete();
    testSignatureArbIntAccepted();
    testSignaturePackedUnionIncomplete();
    testSignatureMemberTypeAccepted();
    testCaptureLifetimePropagation();
    testCaptureNullSafe();
    testCaptureDoubleFree();
    testDeadArmSkipped();
    testFixture("tests/analyzers/fnptr_opt_aggregate.zig", "fixture fnptr_opt_aggregate", @intCast(i32, 0), @intCast(i32, 0));
    testFixture("tests/analyzers/capture_lifetime.zig", "fixture capture_lifetime", @intCast(i32, 0), @intCast(i32, 1));
    testFixture("tests/analyzers/capture_double_free.zig", "fixture capture_double_free", @intCast(i32, 1), @intCast(i32, -1));
    testFixture("tests/analyzers/dead_arm.zig", "fixture dead_arm", @intCast(i32, 0), @intCast(i32, 0));
    testFixture("tests/analyzers/surface_types.zig", "fixture surface_types", @intCast(i32, 0), @intCast(i32, 0));
    var msg: []const u8 = "Analyzer tests passed.\n";
    pal.stdout_write(msg);
}
