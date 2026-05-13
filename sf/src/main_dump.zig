const alloc_mod = @import("allocator.zig");
const Sand = alloc_mod.Sand;
const CompilerAlloc = alloc_mod.CompilerAlloc;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const sm_mod = @import("source_manager.zig");
const SourceManager = sm_mod.SourceManager;
const diag_mod = @import("diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const nm_mod = @import("name_mangler.zig");
const NameMangler = nm_mod.NameMangler;
const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const lexer_mod = @import("lexer.zig");
const pal = @import("pal.zig");
const parser_mod = @import("parser.zig");
const ast_mod = @import("ast.zig");
const dump_tokens = @import("dump_tokens.zig");
const dump_ast = @import("dump_ast.zig");

pub const ColorMode = enum(u8) {
    auto,
    always,
    never,
};

pub const ErrorFormat = enum(u8) {
    human,
    json,
    sarif,
};

pub const CompilerCli = struct {
    input_file: []const u8,
    output_dir: []const u8,
    dump_tokens: bool,
    dump_ast: bool,
    dump_types: bool,
    dump_lir: bool,
    max_mem: u32,
    max_errors: u32,
    color: ColorMode,
    error_format: ErrorFormat,
    warnings_as_errors: bool,
    quiet: bool,
    print_usage: bool,
    test_mode: bool,
    sanity_test_mode: bool,
    track_memory: bool,
    include_dirs: [16][]const u8,
    include_count: u32,
};

pub const CompilerContext = struct {
    cli: CompilerCli,
    alloc: *CompilerAlloc,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    source_man: *SourceManager,
    name_mangler: *NameMangler,
};

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var cli = parseArgs();
    if (cli.sanity_test_mode) {
        var compiler_alloc = alloc_mod.initCompilerAlloc();
        var perm_sand = compiler_alloc.permanent;
        var interner = interner_mod.stringInternerInit(&perm_sand, 4);
        var source_man = sm_mod.sourceManagerInit(&perm_sand);
        var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
        compiler_alloc.permanent = perm_sand;
        token_mod.initKeywordTable(&perm_sand);
        lexer_mod.lexerTestSanityCheck();
        return;
    }
    if (cli.test_mode) {
        const msg: []const u8 = "error: use test_main.zig for test mode\n";
        pal.stderr_write(msg);
        pal.exit(1);
        return;
    }
    if (cli.input_file.len == 0) {
        printUsage();
        return;
    }
    if (cli.dump_tokens) {
        var compiler_alloc = alloc_mod.initCompilerAlloc();
        var perm_sand = compiler_alloc.permanent;
        var interner = interner_mod.stringInternerInit(&perm_sand, 4);
        var source_man = sm_mod.sourceManagerInit(&perm_sand);
        var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
        compiler_alloc.permanent = perm_sand;
        token_mod.initKeywordTable(&perm_sand);
        var source = pal.readFile(cli.input_file, &perm_sand) orelse {
            const msg: []const u8 = "error: could not read input file\n";
            pal.stderr_write(msg);
            pal.exit(1);
            return;
        };
        var module_sand = compiler_alloc.module;
        var lex = lexer_mod.lexerInit(source, 0, &interner, &diag, &module_sand);
        dump_tokens.dumpTokens(&lex, &interner);
        return;
    }
    if (cli.dump_ast) {
        var compiler_alloc = alloc_mod.initCompilerAlloc();
        var perm_sand = compiler_alloc.permanent;
        var interner = interner_mod.stringInternerInit(&perm_sand, 4);
        var source_man = sm_mod.sourceManagerInit(&perm_sand);
        var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
        compiler_alloc.permanent = perm_sand;
        token_mod.initKeywordTable(&perm_sand);
        var source = pal.readFile(cli.input_file, &perm_sand) orelse {
            const msg: []const u8 = "error: could not read input file\n";
            pal.stderr_write(msg);
            pal.exit(1);
            return;
        };
        var module_sand = compiler_alloc.module;
        var lex = lexer_mod.lexerInit(source, 0, &interner, &diag, &module_sand);
        var count: usize = 0;
        while (true) {
            var tok = lexer_mod.lexerNextToken(&lex);
            count += 1;
            if (tok.kind == TokenKind.eof) break;
        }
        var token_mem = alloc_mod.sandAlloc(&module_sand, count * @sizeOf(Token), @alignOf(Token)) catch unreachable;
        var tokens = @ptrCast([*]Token, token_mem);
        var lex2 = lexer_mod.lexerInit(source, 0, &interner, &diag, &module_sand);
        var j: usize = 0;
        while (j < count) {
            tokens[j] = lexer_mod.lexerNextToken(&lex2);
            j += 1;
        }
        var store = ast_mod.astStoreInit(&module_sand);
        var p = parser_mod.parserInit(tokens[0..count], source, &store, &interner, &diag, &module_sand);
        var root = parser_mod.parserParseModuleRoot(&p) catch {
            const msg: []const u8 = "error: parse failed\n";
            pal.stderr_write(msg);
            pal.exit(1);
            return;
        };
        dump_ast.dumpAst(&store, root, &interner);
        return;
    }
    var compiler_alloc = alloc_mod.initCompilerAlloc();
    compiler_alloc.max_mem = cli.max_mem;
    var perm_sand = compiler_alloc.permanent;
    var interner = interner_mod.stringInternerInit(&perm_sand, 4);
    var source_man = sm_mod.sourceManagerInit(&perm_sand);
    var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
    diag.max_diagnostics = @intCast(usize, cli.max_errors);
    compiler_alloc.permanent = perm_sand;
    token_mod.initKeywordTable(&perm_sand);
    var source = pal.readFile(cli.input_file, &perm_sand) orelse {
        const msg: []const u8 = "error: could not read input file\n";
        pal.stderr_write(msg);
        pal.exit(1);
        return;
    };
    var module_sand = compiler_alloc.module;
    var string_interner = interner;
    var name_mangler = nm_mod.nameManglerInit();
    var ctx = CompilerContext{
        .cli = cli,
        .alloc = &compiler_alloc,
        .interner = &string_interner,
        .diag = &diag,
        .source_man = &source_man,
        .name_mangler = &name_mangler,
    };
    runCompiler(source, &ctx);
    var peak = alloc_mod.checkCombinedPeak(&compiler_alloc);
    if (cli.track_memory) {
        var peak_msg: []const u8 = "Peak memory: ";
        pal.stdout_write(peak_msg);
        var buf: [32]u8 = undefined;
        var s = formatU32(peak, buf[0..], 32);
        pal.stdout_write(s);
        var nl2: []const u8 = " bytes\n";
        pal.stdout_write(nl2);
    }
}

fn printUsage() void {
    var msg: []const u8 = "usage: zig1 [options] <file.zig>\n  --test, -t       Run tests\n  --dump-tokens    Dump token stream\n  --dump-ast       Dump AST\n";
    pal.stdout_write(msg);
}

fn parseArgs() CompilerCli {
    const empty_str: []const u8 = "";
    const dot_str: []const u8 = ".";
    var cli = CompilerCli{
        .input_file = empty_str,
        .output_dir = dot_str,
        .dump_tokens = false,
        .dump_ast = false,
        .dump_types = false,
        .dump_lir = false,
        .max_mem = @intCast(u32, 16 * 1024 * 1024),
        .max_errors = @intCast(u32, 256),
        .color = ColorMode.auto,
        .error_format = ErrorFormat.human,
        .warnings_as_errors = false,
        .quiet = false,
        .print_usage = false,
        .test_mode = false,
        .sanity_test_mode = false,
        .track_memory = false,
        .include_dirs = undefined,
        .include_count = @intCast(u32, 0),
    };
    var include_idx: u32 = 0;
    var i: i32 = 0;
    var argc = pal.argCount();
    while (i < argc) {
        var arg = pal.argGet(i);
        if (matchFlag(arg, s_help) or matchFlag(arg, s_h)) {
            cli.print_usage = true;
        } else if (matchFlag(arg, s_test) or matchFlag(arg, s_t)) {
            cli.test_mode = true;
        } else if (matchFlag(arg, s_sanity_test)) {
            cli.sanity_test_mode = true;
        } else if (matchFlag(arg, s_output) or matchFlag(arg, s_o)) {
            i += 1;
            if (i < argc) {
                cli.output_dir = pal.argGet(i);
            }
        } else if (matchFlag(arg, s_color) or matchFlag(arg, s_c)) {
            i += 1;
            if (i < argc) {
                cli.color = parseColorMode(pal.argGet(i));
            }
        } else if (matchFlag(arg, s_error_format) or matchFlag(arg, s_e)) {
            i += 1;
            if (i < argc) {
                cli.error_format = parseErrorFormat(pal.argGet(i));
            }
        } else if (matchFlag(arg, s_warnings_as_errors) or matchFlag(arg, s_w)) {
            cli.warnings_as_errors = true;
        } else if (matchFlag(arg, s_quiet) or matchFlag(arg, s_q)) {
            cli.quiet = true;
        } else if (matchFlag(arg, s_max_mem) or matchFlag(arg, s_m)) {
            i += 1;
            if (i < argc) {
                cli.max_mem = parseSize(pal.argGet(i));
            }
        } else if (matchFlag(arg, s_max_errors) or matchFlag(arg, s_e)) {
            i += 1;
            if (i < argc) {
                cli.max_errors = parseU32(pal.argGet(i));
            }
        } else if (matchFlag(arg, s_track_memory)) {
            cli.track_memory = true;
        } else if (matchFlag(arg, s_include) or matchFlag(arg, s_I)) {
            i += 1;
            if (i < argc and include_idx < 16) {
                cli.include_dirs[@intCast(usize, include_idx)] = pal.argGet(i);
                include_idx += 1;
                cli.include_count = @intCast(u32, include_idx);
            }
        } else if (matchFlag(arg, s_dump_tokens)) {
            cli.dump_tokens = true;
        } else if (matchFlag(arg, s_dump_ast)) {
            cli.dump_ast = true;
        } else if (matchFlag(arg, s_dump_types)) {
            cli.dump_types = true;
        } else if (matchFlag(arg, s_dump_lir)) {
            cli.dump_lir = true;
        } else if (arg.len > 0 and arg[0] == '-') {
            const msg: []const u8 = "error: unknown flag\n";
            pal.stderr_write(msg);
            pal.exit(1);
            return cli;
        } else {
            cli.input_file = arg;
        }
        i += 1;
    }
    return cli;
}

const s_test: []const u8 = "--test";
const s_sanity_test: []const u8 = "--sanity-test";
const s_help: []const u8 = "--help";
const s_h: []const u8 = "-h";
const s_t: []const u8 = "-t";
const s_output: []const u8 = "--output";
const s_o: []const u8 = "-o";
const s_color: []const u8 = "--color";
const s_c: []const u8 = "-c";
const s_error_format: []const u8 = "--error-format";
const s_warnings_as_errors: []const u8 = "--warnings-as-errors";
const s_w: []const u8 = "-w";
const s_quiet: []const u8 = "--quiet";
const s_q: []const u8 = "-q";
const s_max_mem: []const u8 = "--max-mem";
const s_m: []const u8 = "-m";
const s_max_errors: []const u8 = "--max-errors";
const s_e: []const u8 = "-e";
const s_track_memory: []const u8 = "--track-memory";
const s_dump_tokens: []const u8 = "--dump-tokens";
const s_dump_ast: []const u8 = "--dump-ast";
const s_dump_types: []const u8 = "--dump-types";
const s_dump_lir: []const u8 = "--dump-lir";
const s_include: []const u8 = "--include";
const s_I: []const u8 = "-I";

fn matchFlag(arg: []const u8, flag: []const u8) bool {
    var j: usize = 0;
    while (j < arg.len and j < flag.len) {
        if (arg[j] != flag[j]) return false;
        j += 1;
    }
    return j == arg.len and j == flag.len;
}

fn getByte(s: []const u8, i: usize) u8 {
    if (i < s.len) return s[i];
    return 0;
}

fn parseSize(s: []const u8) u32 {
    var result: u32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        var c = s[i];
        if (c >= '0' and c <= '9') {
            result = result * 10 + @intCast(u32, c - '0');
        } else if (c == 'k' or c == 'K') {
            result = result * 1024;
        } else if (c == 'm' or c == 'M') {
            result = result * 1024 * 1024;
        }
        i += 1;
    }
    return result;
}

fn parseU32(s: []const u8) u32 {
    var result: u32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        var c = s[i];
        if (c >= '0' and c <= '9') {
            result = result * 10 + @intCast(u32, c - '0');
        }
        i += 1;
    }
    return result;
}

fn parseColorMode(s: []const u8) ColorMode {
    var i: usize = 0;
    while (i < s.len) {
        var c = s[i];
        if (c == 'a') return ColorMode.always;
        if (c == 'n') return ColorMode.never;
        i += 1;
    }
    return ColorMode.auto;
}

fn parseErrorFormat(s: []const u8) ErrorFormat {
    var i: usize = 0;
    while (i < s.len) {
        var c = s[i];
        if (c == 'j') return ErrorFormat.json;
        i += 1;
    }
    return ErrorFormat.human;
}

fn cstrToSlice(ptr: [*]const u8) []const u8 {
    var len: usize = 0;
    while (ptr[len] != 0) { len += 1; }
    return ptr[0..len];
}

fn runCompiler(source: []const u8, ctx: *CompilerContext) void {
    var arena = alloc_mod.initCompilerAlloc();
    _ = source;
    _ = ctx;
    _ = arena;
}

fn formatU32(val: u32, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + v % 10);
            v = v / 10;
            idx -= 1;
        }
    }
    var start2 = idx + 1;
    return buf[start2 .. buf_len - 1];
}

fn phase_ImportResolution(ctx: *CompilerContext) void {
    _ = ctx;
}

fn phase_SymbolRegistration(ctx: *CompilerContext) void {
    _ = ctx;
}

fn phase_TypeResolution(ctx: *CompilerContext) void {
    _ = ctx;
}

fn phase_SemanticAnalysis(ctx: *CompilerContext) void {
    _ = ctx;
}

fn phase_ASTLowering(ctx: *CompilerContext) void {
    _ = ctx;
}

fn phase_C89Emission(ctx: *CompilerContext) void {
    _ = ctx;
}
