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

pub fn main() void {
    pal.initArgs(0, undefined);
    testResolveIntLiteral();
    testResolveBoolLiteral();
    testResolvePtrType();
    var msg: []const u8 = "Semantic analysis tests passed.\n";
    pal.stdout_write(msg);
}
