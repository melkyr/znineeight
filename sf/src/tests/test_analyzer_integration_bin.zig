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

var perm_buf: [2097152]u8 = undefined;
var scratch_buf: [262144]u8 = undefined;
var type_buf: [131072]u8 = undefined;
var tok_buf: [32768]Token = undefined;

fn testFile(path: []const u8, name: []const u8) void {
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);

    token_mod.initKeywordTable(&perm);

    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);

    var content = pal.readFile(path, &scratch) orelse {
        var emsg: []const u8 = "FAIL: could not read file: ";
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
        tok_buf[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }

    var store = ast_mod.astStoreInit(&perm);
    var p = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch {
        var emsg: []const u8 = "FAIL: parse error: ";
        pal.stderr_write(emsg);
        pal.stderr_write(path);
        var nl: []const u8 = "\n";
        pal.stderr_write(nl);
        pal.exit(1);
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

    if (diag_mod.diagnosticCollectorHasErrors(&diag)) {
        var emsg: []const u8 = "FAIL: analyzer errors in ";
        pal.stderr_write(emsg);
        pal.stderr_write(name);
        var nl: []const u8 = "\n";
        pal.stderr_write(nl);
        pal.exit(1);
    }

    var okmsg: []const u8 = "  ok ";
    pal.stderr_write(okmsg);
    pal.stderr_write(name);
    var nl3: []const u8 = "\n";
    pal.stderr_write(nl3);
}

pub fn main() void {
    pal.initArgs(@intCast(i32, 0), undefined);

    var m: []const u8 = "start\n";
    pal.stderr_write(m);

    var p_hello: []const u8 = "examples/hello/main.zig";
    var n_hello: []const u8 = "hello (simple)";
    testFile(p_hello, n_hello);
    var p_fib: []const u8 = "examples/fibonacci/main.zig";
    var n_fib: []const u8 = "fibonacci (simple)";
    testFile(p_fib, n_fib);

    var msg: []const u8 = "Integration tests passed.\n";
    pal.stdout_write(msg);
}
