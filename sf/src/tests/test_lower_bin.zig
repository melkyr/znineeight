const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const Token = @import("../token.zig").Token;
const TokenKind = @import("../token.zig").TokenKind;
const token_mod = @import("../token.zig");
const lexer_mod = @import("../lexer.zig");
const parser_mod = @import("../parser.zig");
const ast_mod = @import("../ast.zig");
const AstStore = ast_mod.AstStore;
const AstKind = ast_mod.AstKind;
const pal = @import("../pal.zig");
const az_mod = @import("../analyzer.zig");
const AnalyzerContext = az_mod.AnalyzerContext;
const sym_mod = @import("../symbol_table.zig");
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const type_mod = @import("../type_registry.zig");
const resolved_mod = @import("../resolved_type_table.zig");
const coercion_mod = @import("../coercion.zig");
const lower_mod = @import("../lower.zig");
const LirLowerer = lower_mod.LirLowerer;
const SemanticContext = lower_mod.SemanticContext;
const hash_mod = @import("../util/hash.zig");

var perm_buf: [2097152]u8 = undefined;
var scratch_buf: [262144]u8 = undefined;
var type_buf: [131072]u8 = undefined;
var tok_buf: [32768]Token = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "FAIL: ";
    pal.stderr_write(p);
    pal.stderr_write(msg);
    var n: []const u8 = "\n";
    pal.stderr_write(n);
    pal.exit(1);
}

fn testLower() void {
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);

    var path: []const u8 = "sf/src/tests/lower_test/main.zig";
    var content = pal.readFile(path, &scratch) orelse {
        var r: []const u8 = "FAIL: could not read lower_test/main.zig";
        pal.stderr_write(r);
        pal.exit(1);
        return;
    };

    var tok_len: usize = 0;
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), &interner, &diag, &scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tok_buf[@intCast(usize, tok_len)] = t;
        tok_len += @intCast(usize, 1);
        if (t.kind == TokenKind.eof) break;
    }

    var store = ast_mod.astStoreInit(&perm);
    var p = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch {
        var pe: []const u8 = "FAIL: parse error";
        pal.stderr_write(pe);
        pal.exit(1);
        return;
    };

    alloc_mod.sandReset(&scratch);

    var type_db = alloc_mod.sandInit(type_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);

    var sym_table = sym_mod.symbolTableInit(&scratch);
    var sym_reg = sym_mod.symbolRegistryInit(&scratch);
    var resolved = resolved_mod.resolvedTypeTableInit(&scratch);
    var coercions = coercion_mod.coercionTableInit(&scratch);

    var ac = AnalyzerContext{
        .store = &store,
        .registry = &typereg,
        .interner = &interner,
        .diag = &diag,
        .symbols = &sym_table,
        .alloc = &scratch,
        .current_fn_name = @intCast(u32, 0),
        .defer_queue_items = undefined,
        .defer_queue_len = @intCast(usize, 0),
        .defer_queue_cap = @intCast(usize, 0),
        .defer_queue_alloc = &scratch,
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
    };
    az_mod.runAllAnalyzers(&ac, ast_root);

    var enum_value_table = hash_mod.u32ToU32MapInit(&scratch);
    var call_arg_types = hash_mod.u32ToU32MapInit(&scratch);
    var comptime_values = hash_mod.u32ToU64MapInit(&scratch);
    var error_code_registry = hash_mod.u32ToU32MapInit(&scratch);
    var ctx = SemanticContext{
        .store = &store,
        .registry = &typereg,
        .symbol_tables = &sym_reg,
        .resolved_types = &resolved,
        .coercions = &coercions,
        .diag = &diag,
        .has_symbols = @intCast(u8, 0),
        .enum_value_table = &enum_value_table,
        .call_arg_types = &call_arg_types,
        .comptime_values = &comptime_values,
        .error_code_registry = &error_code_registry,
        .source_file_id = @intCast(u32, 0),
    };

    var lowerer = lower_mod.lowererInit(&ctx, &scratch);

    var root = ast_mod.astStoreNodeAt(&store, ast_root);
    var decls = ast_mod.astStoreNodeExtraChildren(&store, ast_root);
    var di: usize = 0;
    var found_count: u32 = @intCast(u32, 0);
    var no_blocks: []const u8 = "function has no blocks";
    var expected_5: []const u8 = "expected at least 5 functions in lower_test/main.zig";
    while (di < decls.len) : (di += @intCast(usize, 1)) {
        var decl = ast_mod.astStoreNodeAt(&store, decls[di]);
        if (decl.kind == AstKind.fn_decl) {
            var lf = lower_mod.lowerFn(&lowerer, decls[di]);
            found_count = found_count + @intCast(u32, 1);
            if (lf.blocks.len == @intCast(usize, 0)) {
                fail(no_blocks);
            }
        }
    }

    if (found_count < @intCast(u32, 5)) {
        fail(expected_5);
    }

    var ok: []const u8 = "Lowering tests passed.\n";
    pal.stdout_write(ok);
}

pub fn main() void {
    pal.initArgs(@intCast(i32, 0), undefined);
    var start: []const u8 = "start\n";
    pal.stderr_write(start);
    testLower();
}
