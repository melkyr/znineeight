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
    var type_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), type_mod.TYPE_VOID);
    var param_node = ast_mod.astStoreAddNode(&store, AstKind.param_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), type_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var param_buf: [1]u32 = undefined;
    param_buf[0] = param_node;
    var param_payload = ast_mod.astStoreAddExtraChildren(&store, param_buf[0..1]);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u16, param_payload >> @intCast(u32, 16)), .params_count = @intCast(u16, 1), .return_type_node = @intCast(u32, 0) };
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
    var type_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), type_mod.TYPE_U8);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u16, 0), .params_count = @intCast(u16, 0), .return_type_node = type_node };
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
    var type_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), fnid);
    var param_node = ast_mod.astStoreAddNode(&store, AstKind.param_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), type_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var param_buf: [1]u32 = undefined;
    param_buf[0] = param_node;
    var param_payload = ast_mod.astStoreAddExtraChildren(&store, param_buf[0..1]);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u16, param_payload >> @intCast(u32, 16)), .params_count = @intCast(u16, 1), .return_type_node = @intCast(u32, 0) };
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
    var type_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), anid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 42));
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var as_node = ast_mod.astStoreAddNode(&store, AstKind.assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 10), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 99));
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 77));
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var addr_node = ast_mod.astStoreAddNode(&store, AstKind.address_of, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var pn: []const u8 = "p";
    var pid = interner_mod.stringInternerIntern(&interner, pn);
    var p_id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), pid);
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
    var arr_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var callee = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), sand_nid);
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
    var other_callee = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), other_nid);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), free_nid);
    var ptr_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var arg0_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 99));
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
    var other_callee = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), other_nid);
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
    var sa_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), sa_id);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), af_id);
    var pid_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), af_id);
    var pid_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), af_id);
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    var pid_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), pr_id);
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    var pid_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), af_id);
    var arg_buf: [2]u32 = undefined;
    arg_buf[0] = @intCast(u32, 0);
    var pid_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), sa_id);
    var arg_buf2: [2]u32 = undefined;
    arg_buf2[0] = @intCast(u32, 0);
    arg_buf2[1] = @intCast(u32, 0);
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf2[0..2]);
    var alloc_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), payload);
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var as_node = ast_mod.astStoreAddNode(&store, AstKind.assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, alloc_node, @intCast(u32, 0), @intCast(u32, 0));
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var as_node = ast_mod.astStoreAddNode(&store, AstKind.assign, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), id_node, null_node, @intCast(u32, 0), @intCast(u32, 0));
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
    var id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var ptr_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var arg_buf: [1]u32 = undefined;
    arg_buf[0] = ptr_node;
    var payload = ast_mod.astStoreAddExtraChildren(&store, arg_buf[0..1]);
    var callee_id_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
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
    var callee_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), af_id);
    var pid_node = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
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
    var ret_node = ast_mod.astStoreAddNode(&store, AstKind.return_stmt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var ret_buf: [1]u32 = undefined;
    ret_buf[0] = ret_node;
    var block_payload = ast_mod.astStoreAddExtraChildren(&store, ret_buf[0..1]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), block_payload);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u16, 0), .params_count = @intCast(u16, 0), .return_type_node = @intCast(u32, 0) };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), body_node, @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    var decl_buf: [1]u32 = undefined;
    decl_buf[0] = fn_node;
    var mr_payload = ast_mod.astStoreAddExtraChildren(&store, decl_buf[0..1]);
    var mr_node = ast_mod.astStoreAddNode(&store, AstKind.module_root, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), mr_payload);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.error_count != @intCast(usize, 0)) {
        var fmsg: []const u8 = "testRunAllAnalyzers: expected 0 errors\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testRunAllAnalyzers";
    helpers.ok(ok_msg);
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
    var msg: []const u8 = "Analyzer tests passed.\n";
    pal.stdout_write(msg);
}
