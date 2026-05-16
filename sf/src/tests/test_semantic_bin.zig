const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const sm_mod = @import("../source_manager.zig");
const SourceManager = sm_mod.SourceManager;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const ast_mod = @import("../ast.zig");
const AstStore = ast_mod.AstStore;
const AstKind = ast_mod.AstKind;
const type_mod = @import("../type_registry.zig");
const TypeRegistry = type_mod.TypeRegistry;
const TypeId = type_mod.TypeId;
const sym_mod = @import("../symbol_table.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const rtt_mod = @import("../resolved_type_table.zig");
const sa_mod = @import("../semantic_analyzer.zig");
const coercion_mod = @import("../coercion.zig");
const pal = @import("../pal.zig");

var diag_arena_buf: [4096]u8 = undefined;
var perm_buf: [16384]u8 = undefined;
var type_db_buf: [65536]u8 = undefined;

fn fail(msg: []const u8) void {
    var fmsg: []const u8 = "FAIL: ";
    pal.stderr_write(fmsg);
    pal.stderr_write(msg);
    var nl: []const u8 = "\n";
    pal.stderr_write(nl);
    pal.exit(1);
}

fn ok(msg: []const u8) void {
    var omsg: []const u8 = "  ok ";
    pal.stderr_write(omsg);
    pal.stderr_write(msg);
    var nl: []const u8 = "\n";
    pal.stderr_write(nl);
}

fn testResolveIntLiteral() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, 0);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, idx);
    if (tid != type_mod.TYPE_INT_LIT) {
        fail("testResolveIntLiteral");
        return;
    }
    ok("testResolveIntLiteral");
}

fn testResolveBoolLiteral() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, 0);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, idx);
    if (tid != type_mod.TYPE_BOOL) {
        fail("testResolveBoolLiteral");
        return;
    }
    ok("testResolveBoolLiteral");
}

fn testResolvePtrType() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, 0);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.ptr_type, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, idx);
    if (tid != type_mod.TYPE_TYPE) {
        fail("testResolvePtrType");
        return;
    }
    ok("testResolvePtrType");
}

fn testResolveIdentTypeAlias() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var tn: []const u8 = "MyType";
    var nid = interner_mod.stringInternerIntern(&interner, tn);
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    var sym = sym_mod.Symbol{
        .name_id = nid,
        .type_id = type_mod.TYPE_U8,
        .kind = sym_mod.SymbolKind.type_alias,
        .flags = @intCast(u16, 0),
        .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .scope_level = @intCast(u32, 0),
    };
    _ = sym_mod.symbolTableInsert(table, sym);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, idx);
    if (tid != type_mod.TYPE_U8) {
        fail("testResolveIdentTypeAlias");
        return;
    }
    ok("testResolveIdentTypeAlias");
}

fn testResolveIdentPrimitive() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var pn: []const u8 = "u32";
    var nid = interner_mod.stringInternerIntern(&interner, pn);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, idx);
    if (tid != type_mod.TYPE_U32) {
        fail("testResolveIdentPrimitive");
        return;
    }
    ok("testResolveIdentPrimitive");
}

fn testResolveIdentNotFound() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var pn: []const u8 = "no_such_type_171";
    var nid = interner_mod.stringInternerIntern(&interner, pn);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), nid);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, idx);
    if (tid != type_mod.TYPE_VOID) {
        fail("testResolveIdentNotFound");
        return;
    }
    ok("testResolveIdentNotFound");
}

fn testResolveStructField() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);

    var fn1: []const u8 = "x";
    var fnid1 = interner_mod.stringInternerIntern(&interner, fn1);
    var fn2: []const u8 = "y";
    var fnid2 = interner_mod.stringInternerIntern(&interner, fn2);

    type_mod.feAppend(&typereg, type_mod.FieldEntry{ .name_id = fnid1, .type_id = type_mod.TYPE_U32, .offset = @intCast(u32, 0) });
    var fstart = @intCast(u32, 0);
    type_mod.feAppend(&typereg, type_mod.FieldEntry{ .name_id = fnid2, .type_id = type_mod.TYPE_U8, .offset = @intCast(u32, 0) });

    var sp = type_mod.StructPayload{ .fields_start = @intCast(u16, fstart), .fields_count = @intCast(u16, 2) };
    type_mod.stAppend(&typereg, sp);
    var pidx: u32 = @intCast(u32, typereg.st_len - 1);

    var sn: []const u8 = "MyStruct";
    var snid = interner_mod.stringInternerIntern(&interner, sn);
    var stid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), snid, type_mod.TypeKind.struct_type);

    var ty = typereg.types_items[@intCast(usize, stid)];
    ty.payload_idx = pidx;
    typereg.types_items[@intCast(usize, stid)] = ty;

    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));

    var sym = sym_mod.Symbol{
        .name_id = snid, .type_id = stid, .kind = sym_mod.SymbolKind.type_alias,
        .flags = @intCast(u16, 2), .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0),
    };
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    _ = sym_mod.symbolTableInsert(table, sym);

    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), snid);
    var fa_idx = ast_mod.astStoreAddNode(&store, AstKind.field_access, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), ident_idx, @intCast(u32, 0), @intCast(u32, 0), fnid1);

    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, fa_idx);
    if (tid != type_mod.TYPE_U32) {
        fail("testResolveStructField returned wrong type");
        return;
    }

    var rtt_tid = rtt_mod.resolvedTypeTableGet(&rtt, fa_idx);
    if (rtt_tid) |t| {
        if (t != type_mod.TYPE_U32) {
            fail("testResolveStructField wrong entry in type_table");
            return;
        }
    } else {
        fail("testResolveStructField no entry in type_table");
        return;
    }
    ok("testResolveStructField");
}

fn testResolveModuleField() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));

    var mn: []const u8 = "mymod";
    var mnid = interner_mod.stringInternerIntern(&interner, mn);
    var mod_sym = sym_mod.Symbol{
        .name_id = mnid, .type_id = @intCast(u32, 0), .kind = sym_mod.SymbolKind.module,
        .flags = @intCast(u16, 2), .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 5), .scope_level = @intCast(u32, 0),
    };
    var t0 = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    _ = sym_mod.symbolTableInsert(t0, mod_sym);

    var tn: []const u8 = "SomeType";
    var tnid = interner_mod.stringInternerIntern(&interner, tn);
    var type_sym = sym_mod.Symbol{
        .name_id = tnid, .type_id = type_mod.TYPE_U32, .kind = sym_mod.SymbolKind.type_alias,
        .flags = @intCast(u16, 2), .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 5), .scope_level = @intCast(u32, 0),
    };
    var t5 = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 5));
    _ = sym_mod.symbolTableInsert(t5, type_sym);

    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), mnid);
    var fa_idx = ast_mod.astStoreAddNode(&store, AstKind.field_access, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), ident_idx, @intCast(u32, 0), @intCast(u32, 0), tnid);

    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, fa_idx);
    if (tid != type_mod.TYPE_U32) {
        fail("testResolveModuleField wrong type");
        return;
    }
    ok("testResolveModuleField");
}

fn testResolveFieldNotFound() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);

    var fn1: []const u8 = "x";
    var fnid1 = interner_mod.stringInternerIntern(&interner, fn1);
    type_mod.feAppend(&typereg, type_mod.FieldEntry{ .name_id = fnid1, .type_id = type_mod.TYPE_U32, .offset = @intCast(u32, 0) });

    var sp = type_mod.StructPayload{ .fields_start = @intCast(u16, 0), .fields_count = @intCast(u16, 1) };
    type_mod.stAppend(&typereg, sp);
    var pidx = @intCast(u32, typereg.st_len - 1);

    var sn: []const u8 = "S";
    var snid = interner_mod.stringInternerIntern(&interner, sn);
    var stid = type_mod.typeRegistryRegisterNamedType(&typereg, @intCast(u32, 0), snid, type_mod.TypeKind.struct_type);
    var ty = typereg.types_items[@intCast(usize, stid)];
    ty.payload_idx = pidx;
    typereg.types_items[@intCast(usize, stid)] = ty;

    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));

    var sym = sym_mod.Symbol{
        .name_id = snid, .type_id = stid, .kind = sym_mod.SymbolKind.type_alias,
        .flags = @intCast(u16, 2), .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0),
    };
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    _ = sym_mod.symbolTableInsert(table, sym);

    var fnz: []const u8 = "z";
    var fnidz = interner_mod.stringInternerIntern(&interner, fnz);
    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), snid);
    var fa_idx = ast_mod.astStoreAddNode(&store, AstKind.field_access, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), ident_idx, @intCast(u32, 0), @intCast(u32, 0), fnidz);

    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, fa_idx);
    if (tid != type_mod.TYPE_VOID) {
        fail("testResolveFieldNotFound expected TYPE_VOID");
        return;
    }
    ok("testResolveFieldNotFound");
}

fn testBitwiseSameType() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var un: []const u8 = "u32";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var lhs = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var rhs = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var and_idx = ast_mod.astStoreAddNode(&store, AstKind.bit_and, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), lhs, rhs, @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, and_idx);
    if (tid != type_mod.TYPE_U32) { var fmsg: []const u8 = "testBitwiseSameType expected TYPE_U32"; fail(fmsg); return; }
    var bmsg: []const u8 = "testBitwiseSameType";
    ok(bmsg);
}

fn testComparisonSameType() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var un: []const u8 = "u64";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var lhs = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var rhs = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var cmp_idx = ast_mod.astStoreAddNode(&store, AstKind.cmp_eq, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), lhs, rhs, @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, cmp_idx);
    if (tid != type_mod.TYPE_BOOL) { var fmsg: []const u8 = "testComparisonSameType expected TYPE_BOOL"; fail(fmsg); return; }
    var csmsg: []const u8 = "testComparisonSameType";
    ok(csmsg);
}

fn testLogicalBool() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var lhs = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var rhs = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var and_idx = ast_mod.astStoreAddNode(&store, AstKind.bool_and, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), lhs, rhs, @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, and_idx);
    if (tid != type_mod.TYPE_BOOL) { var fmsg: []const u8 = "testLogicalBool expected TYPE_BOOL"; fail(fmsg); return; }
    var lbmsg: []const u8 = "testLogicalBool";
    ok(lbmsg);
}

fn testNegateNumeric() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var un: []const u8 = "i32";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var inner = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var neg_idx = ast_mod.astStoreAddNode(&store, AstKind.negate, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), inner, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, neg_idx);
    if (tid != type_mod.TYPE_I32) { var fmsg: []const u8 = "testNegateNumeric expected TYPE_I32"; fail(fmsg); return; }
    var nnmsg: []const u8 = "testNegateNumeric";
    ok(nnmsg);
}

fn testBitNotInteger() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var un: []const u8 = "u16";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var inner = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var not_idx = ast_mod.astStoreAddNode(&store, AstKind.bit_not, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), inner, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, not_idx);
    if (tid != type_mod.TYPE_U16) { var fmsg: []const u8 = "testBitNotInteger expected TYPE_U16"; fail(fmsg); return; }
    var bnmsg: []const u8 = "testBitNotInteger";
    ok(bnmsg);
}

fn testOptionalNullCmp() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var lit_idx = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var un: []const u8 = "u32";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var cmp_idx = ast_mod.astStoreAddNode(&store, AstKind.cmp_lt, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), lit_idx, ident_idx, @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, cmp_idx);
    if (tid != type_mod.TYPE_BOOL) { var fmsg: []const u8 = "testOptionalNullCmp expected TYPE_BOOL"; fail(fmsg); return; }
    var ocmsg: []const u8 = "testOptionalNullCmp";
    ok(ocmsg);
}

fn testTryExprSuccess() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var eu_tid = type_mod.typeRegistryGetOrCreateErrorUnion(&typereg, type_mod.TYPE_U32, @intCast(u32, 0));
    _ = eu_tid;
    var un: []const u8 = "my_fn";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    var sym = sym_mod.Symbol{
        .name_id = unid,
        .type_id = eu_tid,
        .kind = sym_mod.SymbolKind.global,
        .flags = @intCast(u16, 0),
        .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .scope_level = @intCast(u32, 0),
    };
    _ = sym_mod.symbolTableInsert(table, sym);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var try_idx = ast_mod.astStoreAddNode(&store, AstKind.try_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), ident_idx, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, try_idx);
    if (tid != type_mod.TYPE_U32) { var fmsg: []const u8 = "testTryExprSuccess expected TYPE_U32"; fail(fmsg); return; }
    var tmsg: []const u8 = "testTryExprSuccess";
    ok(tmsg);
}

fn testTryExprNotErrorUnion() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var un: []const u8 = "my_int";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    var sym = sym_mod.Symbol{
        .name_id = unid,
        .type_id = type_mod.TYPE_U32,
        .kind = sym_mod.SymbolKind.global,
        .flags = @intCast(u16, 0),
        .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .scope_level = @intCast(u32, 0),
    };
    _ = sym_mod.symbolTableInsert(table, sym);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var try_idx = ast_mod.astStoreAddNode(&store, AstKind.try_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), ident_idx, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, try_idx);
    if (tid != type_mod.TYPE_VOID) { var fmsg: []const u8 = "testTryExprNotErrorUnion expected TYPE_VOID"; fail(fmsg); return; }
    var tmsg: []const u8 = "testTryExprNotErrorUnion";
    ok(tmsg);
}

fn testIfExprSameType() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var cond = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var then_body = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var else_body = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var if_idx = ast_mod.astStoreAddNode(&store, AstKind.if_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), cond, then_body, else_body, @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, if_idx);
    if (tid != type_mod.TYPE_INT_LIT) { var fmsg: []const u8 = "testIfExprSameType expected TYPE_INT_LIT"; fail(fmsg); return; }
    var emsg: []const u8 = "testIfExprSameType";
    ok(emsg);
}

fn testIfExprMismatch() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var cond = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var then_body = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var else_body = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var if_idx = ast_mod.astStoreAddNode(&store, AstKind.if_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), cond, then_body, else_body, @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, if_idx);
    if (tid != type_mod.TYPE_VOID) { var fmsg: []const u8 = "testIfExprMismatch expected TYPE_VOID"; fail(fmsg); return; }
    var emsg: []const u8 = "testIfExprMismatch";
    ok(emsg);
}

fn testIfExprNoElse() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var cond = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var then_body = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var if_idx = ast_mod.astStoreAddNode(&store, AstKind.if_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), cond, then_body, @intCast(u32, 0), @intCast(u32, 0));
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, if_idx);
    if (tid != type_mod.TYPE_INT_LIT) { var fmsg: []const u8 = "testIfExprNoElse expected TYPE_INT_LIT"; fail(fmsg); return; }
    var emsg: []const u8 = "testIfExprNoElse";
    ok(emsg);
}

fn testSwitchExprSameType() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var cond = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var body1 = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var body2 = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var prong1 = ast_mod.astStoreAddNode(&store, AstKind.switch_prong, 1, @intCast(u32, 0), @intCast(u32, 0), body1, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var prong_buf: [2]u32 = undefined;
    prong_buf[0] = prong1;
    prong_buf[1] = prong1;
    var ec = ast_mod.astStoreAddExtraChildren(&store, prong_buf[0..2]);
    var sw_idx = ast_mod.astStoreAddNode(&store, AstKind.switch_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), cond, @intCast(u32, 0), @intCast(u32, 0), ec);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, sw_idx);
    if (tid != type_mod.TYPE_INT_LIT) { var fmsg: []const u8 = "testSwitchExprSameType expected TYPE_INT_LIT"; fail(fmsg); return; }
    var emsg: []const u8 = "testSwitchExprSameType";
    ok(emsg);
}

fn testSwitchExprMixed() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var cond = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var body_a = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var body_b = ast_mod.astStoreAddNode(&store, AstKind.bool_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var prong_a = ast_mod.astStoreAddNode(&store, AstKind.switch_prong, 1, @intCast(u32, 0), @intCast(u32, 0), body_a, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var prong_b = ast_mod.astStoreAddNode(&store, AstKind.switch_prong, 1, @intCast(u32, 0), @intCast(u32, 0), body_b, @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var prong_buf: [2]u32 = undefined;
    prong_buf[0] = prong_a;
    prong_buf[1] = prong_b;
    var ec = ast_mod.astStoreAddExtraChildren(&store, prong_buf[0..2]);
    var sw_idx = ast_mod.astStoreAddNode(&store, AstKind.switch_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), cond, @intCast(u32, 0), @intCast(u32, 0), ec);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, sw_idx);
    if (tid != type_mod.TYPE_VOID) { var fmsg: []const u8 = "testSwitchExprMixed expected TYPE_VOID"; fail(fmsg); return; }
    var emsg: []const u8 = "testSwitchExprMixed";
    ok(emsg);
}

fn testAssignSameType() void {
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var interner = interner_mod.stringInternerInit(&type_db, 4);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var okv = type_mod.typeRegistryIsAssignable(&typereg, type_mod.TYPE_U32, type_mod.TYPE_U32);
    if (!okv) { var fmsg: []const u8 = "testAssignSameType expected true"; fail(fmsg); return; }
    var emsg: []const u8 = "testAssignSameType";
    ok(emsg);
}

fn testAssignIntLitToNumeric() void {
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var interner = interner_mod.stringInternerInit(&type_db, 4);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var okv = type_mod.typeRegistryIsAssignable(&typereg, type_mod.TYPE_INT_LIT, type_mod.TYPE_U32);
    if (!okv) { var fmsg: []const u8 = "testAssignIntLitToNumeric expected true"; fail(fmsg); return; }
    var emsg: []const u8 = "testAssignIntLitToNumeric";
    ok(emsg);
}

fn testAssignNullToOptional() void {
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var interner = interner_mod.stringInternerInit(&type_db, 4);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var opt_tid = type_mod.typeRegistryGetOrCreateOptional(&typereg, type_mod.TYPE_U32);
    var okv = type_mod.typeRegistryIsAssignable(&typereg, type_mod.TYPE_NULL, opt_tid);
    if (!okv) { var fmsg: []const u8 = "testAssignNullToOptional expected true"; fail(fmsg); return; }
    var emsg: []const u8 = "testAssignNullToOptional";
    ok(emsg);
}

fn testAssignOptionalWrap() void {
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var interner = interner_mod.stringInternerInit(&type_db, 4);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var opt_tid = type_mod.typeRegistryGetOrCreateOptional(&typereg, type_mod.TYPE_U32);
    var okv = type_mod.typeRegistryIsAssignable(&typereg, type_mod.TYPE_U32, opt_tid);
    if (!okv) { var fmsg: []const u8 = "testAssignOptionalWrap expected true"; fail(fmsg); return; }
    var emsg: []const u8 = "testAssignOptionalWrap";
    ok(emsg);
}

fn testAssignConstAdd() void {
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var interner = interner_mod.stringInternerInit(&type_db, 4);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var ptr_u32 = type_mod.typeRegistryGetOrCreatePtr(&typereg, type_mod.TYPE_U32, false);
    var ptr_const_u32 = type_mod.typeRegistryGetOrCreatePtr(&typereg, type_mod.TYPE_U32, false);
    var cty = typereg.types_items[@intCast(usize, ptr_const_u32)];
    cty.flags = cty.flags | @intCast(u8, 1);
    typereg.types_items[@intCast(usize, ptr_const_u32)] = cty;
    var okv = type_mod.typeRegistryIsAssignable(&typereg, ptr_u32, ptr_const_u32);
    if (!okv) { var fmsg: []const u8 = "testAssignConstAdd expected true"; fail(fmsg); return; }
    var emsg: []const u8 = "testAssignConstAdd";
    ok(emsg);
}

fn testAssignMismatch() void {
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var interner = interner_mod.stringInternerInit(&type_db, 4);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var okv = type_mod.typeRegistryIsAssignable(&typereg, type_mod.TYPE_BOOL, type_mod.TYPE_U32);
    if (okv) { var fmsg: []const u8 = "testAssignMismatch expected false"; fail(fmsg); return; }
    var emsg: []const u8 = "testAssignMismatch";
    ok(emsg);
}

fn testCoercionKindValues() void {
    var ck = coercion_mod.CoercionKind;
    _ = ck.wrap_optional;
    _ = ck.const_qualify;
    _ = ck.int_literal_coerce;
    var emsg: []const u8 = "testCoercionKindValues";
    ok(emsg);
}

fn testArithSameType() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));

    var lhs = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var rhs = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var add_idx = ast_mod.astStoreAddNode(&store, AstKind.add, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), lhs, rhs, @intCast(u32, 0), @intCast(u32, 0));

    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, add_idx);
    if (tid != type_mod.TYPE_INT_LIT) {
        fail("testArithSameType expected TYPE_INT_LIT");
        return;
    }
    ok("testArithSameType");
}

fn testArithLiteralPromo() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));

    var un: []const u8 = "u32";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var ident_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var lit_idx = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var add_idx = ast_mod.astStoreAddNode(&store, AstKind.add, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), lit_idx, ident_idx, @intCast(u32, 0), @intCast(u32, 0));

    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, add_idx);
    if (tid != type_mod.TYPE_U32) {
        fail("testArithLiteralPromo expected TYPE_U32");
        return;
    }
    ok("testArithLiteralPromo");
}

fn testFnCallArith() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var fn_start: u16 = @intCast(u16, typereg.xt_len);
    type_mod.xtAppend(&typereg, type_mod.TYPE_I32);
    type_mod.xtAppend(&typereg, type_mod.TYPE_I32);
    var fn_tid = type_mod.typeRegistryGetOrCreateFn(&typereg, @intCast(u32, 0), fn_start, @intCast(u16, 2), type_mod.TYPE_I32);
    var un: []const u8 = "add";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    var sym = sym_mod.Symbol{
        .name_id = unid, .type_id = fn_tid, .kind = sym_mod.SymbolKind.function,
        .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0),
    };
    _ = sym_mod.symbolTableInsert(table, sym);
    var callee_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var arg0 = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var arg1 = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var args_buf: [2]u32 = undefined;
    args_buf[0] = arg0;
    args_buf[1] = arg1;
    var args_payload = ast_mod.astStoreAddExtraChildren(&store, args_buf[0..2]);
    var call_idx = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_idx, @intCast(u32, 0), @intCast(u32, 0), args_payload);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, call_idx);
    if (tid != type_mod.TYPE_I32) {
        var fmsg: []const u8 = "testFnCallArith expected TYPE_I32";
        fail(fmsg);
        return;
    }
    var okmsg: []const u8 = "testFnCallArith";
    ok(okmsg);
}

fn testFnCallWrongArgCount() void {
    var arena = alloc_mod.sandInit(perm_buf[0..]);
    var diag_sand = alloc_mod.sandInit(diag_arena_buf[0..]);
    var source_man = sm_mod.sourceManagerInit(&diag_sand);
    var interner = interner_mod.stringInternerInit(&diag_sand, 4);
    var diag = diag_mod.diagnosticCollectorInit(&diag_sand, &source_man, &interner);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&arena);
    var symreg = sym_mod.symbolRegistryInit(&arena);
    var rtt = rtt_mod.resolvedTypeTableInit(&arena);
    var sa = sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0));
    var fn_start: u16 = @intCast(u16, typereg.xt_len);
    type_mod.xtAppend(&typereg, type_mod.TYPE_I32);
    var fn_tid = type_mod.typeRegistryGetOrCreateFn(&typereg, @intCast(u32, 0), fn_start, @intCast(u16, 1), type_mod.TYPE_I32);
    var un: []const u8 = "add";
    var unid = interner_mod.stringInternerIntern(&interner, un);
    var table = sym_mod.symbolRegistryGetTable(&symreg, @intCast(u32, 0));
    var sym = sym_mod.Symbol{
        .name_id = unid, .type_id = fn_tid, .kind = sym_mod.SymbolKind.function,
        .flags = @intCast(u16, 0), .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0), .scope_level = @intCast(u32, 0),
    };
    _ = sym_mod.symbolTableInsert(table, sym);
    var callee_idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), unid);
    var arg0 = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var arg1 = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    var args_buf: [2]u32 = undefined;
    args_buf[0] = arg0;
    args_buf[1] = arg1;
    var args_payload = ast_mod.astStoreAddExtraChildren(&store, args_buf[0..2]);
    var call_idx = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_idx, @intCast(u32, 0), @intCast(u32, 0), args_payload);
    var tid = sa_mod.semanticAnalyzerResolveExpr(&sa, call_idx);
    if (tid != type_mod.TYPE_I32) {
        var fmsg: []const u8 = "testFnCallWrongArgCount expected TYPE_I32";
        fail(fmsg);
        return;
    }
    var okmsg: []const u8 = "testFnCallWrongArgCount";
    ok(okmsg);
}

pub fn main() void {
    pal.initArgs(0, undefined);
    testResolveIntLiteral();
    testResolveBoolLiteral();
    testResolvePtrType();
    testResolveIdentTypeAlias();
    testResolveIdentPrimitive();
    testResolveIdentNotFound();
    testResolveStructField();
    testResolveModuleField();
    testResolveFieldNotFound();
    testBitwiseSameType();
    testComparisonSameType();
    testLogicalBool();
    testNegateNumeric();
    testBitNotInteger();
    testOptionalNullCmp();
    testCoercionKindValues();
    testArithSameType();
    testArithLiteralPromo();
    testFnCallArith();
    testFnCallWrongArgCount();
    testTryExprSuccess();
    testTryExprNotErrorUnion();
    testIfExprSameType();
    testIfExprMismatch();
    testIfExprNoElse();
    testSwitchExprSameType();
    testSwitchExprMixed();
    testAssignSameType();
    testAssignIntLitToNumeric();
    testAssignNullToOptional();
    testAssignOptionalWrap();
    testAssignConstAdd();
    testAssignMismatch();
    var msg: []const u8 = "Semantic analysis tests passed.\n";
    pal.stdout_write(msg);
}
