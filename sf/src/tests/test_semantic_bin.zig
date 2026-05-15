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
    testArithSameType();
    testArithLiteralPromo();
    var msg: []const u8 = "Semantic analysis tests passed.\n";
    pal.stdout_write(msg);
}
