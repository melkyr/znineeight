const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const type_mod = @import("../type_registry.zig");
const TypeRegistry = type_mod.TypeRegistry;
const ast_mod = @import("../ast.zig");
const AstStore = ast_mod.AstStore;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const az_mod = @import("../analyzer.zig");
const AnalyzerContext = az_mod.AnalyzerContext;
const pal = @import("../pal.zig");

var type_db_buf: [65536]u8 = undefined;
var arena_buf: [65536]u8 = undefined;

pub fn initTest(arena: *Sand, interner: *StringInterner, typereg: *TypeRegistry, store: *AstStore, diag: *DiagnosticCollector) void {
    arena.* = alloc_mod.sandInit(arena_buf[0..]);
    interner.* = interner_mod.stringInternerInit(arena, 4);
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    typereg.* = type_mod.typeRegistryInit(&type_db, interner);
    type_mod.typeRegistryRegisterPrimitives(typereg);
    store.* = ast_mod.astStoreInit(arena);
    diag.* = diag_mod.diagnosticCollectorInit(arena, undefined, interner);
}

pub fn initCtx(ac: *AnalyzerContext, store: *AstStore, typereg: *TypeRegistry, interner: *StringInterner, diag: *DiagnosticCollector, arena: *Sand) void {
    ac.* = AnalyzerContext{
        .store = store, .registry = typereg, .interner = interner,
        .diag = diag, .alloc = arena, .current_fn_name = @intCast(u32, 0),
        .defer_queue_items = undefined, .defer_queue_len = @intCast(usize, 0),
        .defer_queue_cap = @intCast(usize, 0), .defer_queue_alloc = arena,
        .current_depth = @intCast(u32, 0),
        .null_analysis_mode = @intCast(u8, 0),
    };
}

pub fn fail(msg: []const u8) void {
    var fmsg: []const u8 = "FAIL: ";
    pal.stderr_write(fmsg);
    pal.stderr_write(msg);
    var nl: []const u8 = "\n";
    pal.stderr_write(nl);
    pal.exit(1);
}

pub fn ok(msg: []const u8) void {
    var omsg: []const u8 = "  ok ";
    pal.stderr_write(omsg);
    pal.stderr_write(msg);
    var nl: []const u8 = "\n";
    pal.stderr_write(nl);
}
