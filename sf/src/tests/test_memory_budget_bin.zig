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
const pal = @import("../pal.zig");
const az_mod = @import("../analyzer.zig");
const AnalyzerContext = az_mod.AnalyzerContext;
const sym_mod = @import("../symbol_table.zig");
const SymbolTable = sym_mod.SymbolTable;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const type_mod = @import("../type_registry.zig");

var perm_buf: [4194304]u8 = undefined;
var scratch_buf: [524288]u8 = undefined;
var type_buf: [262144]u8 = undefined;
var tok_buf: [131072]Token = undefined;

fn fail(msg: []const u8) void {
    var fmsg: []const u8 = "FAIL: ";
    pal.stderr_write(fmsg);
    pal.stderr_write(msg);
    var nl: []const u8 = "\n";
    pal.stderr_write(nl);
    pal.exit(1);
}

pub fn main() void {
    pal.initArgs(@intCast(i32, 0), undefined);

    var m: []const u8 = "start\n";
    pal.stderr_write(m);

    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);

    token_mod.initKeywordTable(&perm);

    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);

    var p_wc: []const u8 = "sf/src/tests/worst_case/main.zig";
    var rerr: []const u8 = "FAIL: could not read worst_case/main.zig\n";
    var content = pal.readFile(p_wc, &scratch) orelse {
        pal.stderr_write(rerr);
        pal.exit(1);
        return;
    };

    var tok_len: usize = 0;
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), &interner, &diag, &scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tok_buf[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }

    var store = ast_mod.astStoreInit(&perm);
    var p = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    var perr: []const u8 = "parse error in worst_case/main.zig";
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch {
        fail(perr);
        return;
    };

    alloc_mod.sandReset(&scratch);

    var type_db = alloc_mod.sandInit(type_buf[0..]);
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
    };
    az_mod.runAllAnalyzers(&ac, ast_root);

    var peak_kb: u32 = @intCast(u32, scratch.peak / @intCast(usize, 1024));
    var okmsg: []const u8 = "  ok memory_budget: peak=";
    pal.stderr_write(okmsg);
    writeU32(peak_kb);
    var kmsg: []const u8 = "K\n";
    pal.stderr_write(kmsg);

    if (scratch.peak > az_mod.PER_FUNC_BUDGET) {
        var fmsg: []const u8 = "FAIL: peak exceeds 512KB budget";
        pal.stderr_write(fmsg);
        pal.exit(1);
    }

    var msg: []const u8 = "Memory budget test passed.\n";
    pal.stdout_write(msg);
}

fn writeU32(val: u32) void {
    var buf: [16]u8 = undefined;
    var i: u32 = 16;
    var v = val;
    if (v == 0) {
        buf[15] = 48;
        var s = buf[15..16];
        pal.stderr_write(s);
        return;
    }
    while (v > 0 and i > 0) {
        i -= 1;
        buf[@intCast(usize, i)] = @intCast(u8, @intCast(u32, 48 + @intCast(u32, v % 10)));
        v = v / 10;
    }
    var s = buf[i..16];
    pal.stderr_write(s);
}
