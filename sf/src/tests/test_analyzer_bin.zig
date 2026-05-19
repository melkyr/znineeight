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
    var msg: []const u8 = "Analyzer tests passed.\n";
    pal.stdout_write(msg);
}
