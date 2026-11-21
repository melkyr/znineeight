const pal = @import("pal.zig");
const alloc_mod = @import("allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const token_mod = @import("token.zig");
const lexer_mod = @import("lexer.zig");
const parser_mod = @import("parser.zig");
const ast_mod = @import("ast.zig");
const dump_ast = @import("dump_ast.zig");
const sm_mod = @import("source_manager.zig");
const diag_mod = @import("diagnostics.zig");

var _sand: Sand = undefined;
var _interner: StringInterner = undefined;

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    if (argc < @intCast(i32, 2)) { pal.exit(1); return; }
    var fname_ptr = pal.argGet(1);
    var fname_len: usize = 0;
    while (fname_ptr[fname_len] != 0) { fname_len += 1; }
    var fname = fname_ptr[0..fname_len];

    var sand_buf: [2 * 1024 * 1024]u8 = undefined;
    _sand = alloc_mod.sandInit(sand_buf[0..]);

    _interner = interner_mod.stringInternerInit(&_sand, @intCast(u32, 4));
    token_mod.initKeywordTable(&_sand);
    var source_man = sm_mod.sourceManagerInit(&_sand);
    var diag = diag_mod.diagnosticCollectorInit(&_sand, &source_man, &_interner);

    var source = pal.readFile(fname, &_sand) orelse {
        var msg: []const u8 = "cannot read file\n"; pal.stderr_write(msg); pal.exit(1); return;
    };

    var lex = lexer_mod.lexerInit(source, @intCast(u32, 0), &_interner, &diag, &_sand);
    var count: usize = 0;
    while (true) {
        var tok = lexer_mod.lexerNextToken(&lex);
        count += 1;
        if (tok.kind == token_mod.TokenKind.eof) break;
    }

    var store = ast_mod.astStoreInit(&_sand);
    var token_mem = alloc_mod.sandAlloc(&_sand, count * @sizeOf(token_mod.Token), @alignOf(token_mod.Token)) catch unreachable;
    var tokens = @ptrCast([*]token_mod.Token, token_mem);
    var lex2 = lexer_mod.lexerInit(source, @intCast(u32, 0), &_interner, &diag, &_sand);
    var j: usize = 0;
    while (j < count) { tokens[j] = lexer_mod.lexerNextToken(&lex2); j += 1; }

    var p = parser_mod.parserInit(tokens[0..count], source, &store, &_interner, &diag, &_sand);
    var root = parser_mod.parserParseModuleRoot(&p) catch {
        var msg: []const u8 = "parse failed\n"; pal.stderr_write(msg); pal.exit(1); return;
    };
    dump_ast.dumpAst(&store, root, &_interner);
}
