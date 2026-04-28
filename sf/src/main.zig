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
const pal = @import("pal.zig");

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
    test_mode: bool,
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

pub fn main() void {
    var cli = parseArgs();
    if (cli.test_mode) {
        var compiler_alloc = alloc_mod.initCompilerAlloc();
        var perm_sand = compiler_alloc.permanent;
        var interner = interner_mod.stringInternerInit(&perm_sand, 4);
        var source_man = sm_mod.sourceManagerInit(&perm_sand);
        var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
        compiler_alloc.permanent = perm_sand;
        token_mod.initKeywordTable(&perm_sand);
        const lexer_mod = @import("lexer.zig");
        lexer_mod.lexerRunAllTests();
        return;
    }
    if (cli.input_file.len == 0) {
        printUsage();
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
    var name_mangler = nm_mod.nameManglerInit();
    var ctx = CompilerContext{
        .cli = cli,
        .alloc = &compiler_alloc,
        .interner = &interner,
        .diag = &diag,
        .source_man = &source_man,
        .name_mangler = &name_mangler,
    };
    runCompiler(&ctx);
}

fn runCompiler(ctx: *CompilerContext) void {
    phase_ImportResolution(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        diag_mod.diagnosticCollectorPrintAll(ctx.diag);
        pal.exit(2);
    }
    phase_SymbolRegistration(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    phase_TypeResolution(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        diag_mod.diagnosticCollectorPrintAll(ctx.diag);
        pal.exit(2);
    }
    phase_SemanticAnalysis(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        diag_mod.diagnosticCollectorPrintAll(ctx.diag);
        pal.exit(2);
    }
    phase_LIRLowering(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        diag_mod.diagnosticCollectorPrintAll(ctx.diag);
        pal.exit(2);
    }
    phase_C89Emission(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    diag_mod.diagnosticCollectorPrintAll(ctx.diag);
    if (ctx.cli.warnings_as_errors and diag_mod.diagnosticCollectorWarningCount(ctx.diag) > 0) {
        pal.exit(1);
    }
    _ = ctx.cli.track_memory;
    _ = ctx.alloc.permanent.peak;
    _ = ctx.alloc.module.peak;
    _ = ctx.alloc.scratch.peak;
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

fn phase_LIRLowering(ctx: *CompilerContext) void {
    _ = ctx;
}

fn phase_C89Emission(ctx: *CompilerContext) void {
    _ = ctx;
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
        .test_mode = false,
        .track_memory = false,
        .include_count = @intCast(u32, 0),
        .include_dirs = undefined,
    };
    var argc = pal.argCount();
    var i: i32 = 1;
    const s_dump_tokens: []const u8 = "--dump-tokens";
    const s_dump_ast: []const u8 = "--dump-ast";
    const s_dump_types: []const u8 = "--dump-types";
    const s_dump_lir: []const u8 = "--dump-lir";
    const s_max_mem: []const u8 = "--max-mem";
    const s_max_errors: []const u8 = "--max-errors";
    const s_output_dir: []const u8 = "--output-dir";
    const s_quiet: []const u8 = "--quiet";
    const s_test: []const u8 = "--test";
    const s_warnings: []const u8 = "--warnings-as-errors";
    const s_color: []const u8 = "--color";
    const s_error_format: []const u8 = "--error-format";
    const s_track_memory: []const u8 = "--track-memory";
    const s_include: []const u8 = "-I";
    const s_t: []const u8 = "-t";
    const s_a: []const u8 = "-a";
    const s_y: []const u8 = "-y";
    const s_l: []const u8 = "-l";
    const s_m: []const u8 = "-m";
    const s_e: []const u8 = "-e";
    const s_o: []const u8 = "-o";
    const s_q: []const u8 = "-q";
    const s_W: []const u8 = "-W";
    while (i < argc) {
        var arg_ptr = pal.argGet(i);
        var arg = cstrToSlice(arg_ptr);
        if (arg.len > 0 and arg[0] == '-') {
            if (matchFlag(arg, s_dump_tokens) or matchFlag(arg, s_t)) {
                cli.dump_tokens = true;
            } else if (matchFlag(arg, s_dump_ast) or matchFlag(arg, s_a)) {
                cli.dump_ast = true;
            } else if (matchFlag(arg, s_dump_types) or matchFlag(arg, s_y)) {
                cli.dump_types = true;
            } else if (matchFlag(arg, s_dump_lir) or matchFlag(arg, s_l)) {
                cli.dump_lir = true;
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
            } else if (matchFlag(arg, s_output_dir) or matchFlag(arg, s_o)) {
                i += 1;
                if (i < argc) {
                    cli.output_dir = cstrToSlice(pal.argGet(i));
                }
            } else if (matchFlag(arg, s_quiet) or matchFlag(arg, s_q)) {
                cli.quiet = true;
            } else if (matchFlag(arg, s_test)) {
                cli.test_mode = true;
            } else if (matchFlag(arg, s_warnings) or matchFlag(arg, s_W)) {
                cli.warnings_as_errors = true;
            } else if (matchFlag(arg, s_color)) {
                i += 1;
                if (i < argc) {
                    cli.color = parseColorMode(pal.argGet(i));
                }
            } else if (matchFlag(arg, s_error_format)) {
                i += 1;
                if (i < argc) {
                    cli.error_format = parseErrorFormat(pal.argGet(i));
                }
            } else if (matchFlag(arg, s_track_memory)) {
                cli.track_memory = true;
            } else if (matchFlag(arg, s_include)) {
                i += 1;
                if (i < argc and cli.include_count < 16) {
                    cli.include_dirs[@intCast(usize, cli.include_count)] = cstrToSlice(pal.argGet(i));
                    cli.include_count += 1;
                }
            } else {
                cli.input_file = cstrToSlice(arg_ptr);
            }
        } else {
            cli.input_file = cstrToSlice(arg_ptr);
        }
        i += 1;
    }
    return cli;
}

fn matchFlag(arg: []const u8, flag: []const u8) bool {
    if (arg.len != flag.len) return false;
    var j: usize = 0;
    while (j < arg.len) {
        if (arg[j] != flag[j]) return false;
        j += 1;
    }
    return true;
}

fn cstrToSlice(ptr: [*]const u8) []const u8 {
    var len: usize = 0;
    while (ptr[len] != 0) {
        len += 1;
    }
    return ptr[0..len];
}

fn parseSize(ptr: [*]const u8) u32 {
    var s = cstrToSlice(ptr);
    var val: u32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        var c = s[i];
        if (c >= '0' and c <= '9') {
            val = val * 10 + @intCast(u32, c - '0');
        } else if (c == 'k' or c == 'K') {
            val = val * 1024;
        } else if (c == 'm' or c == 'M') {
            val = val * 1024 * 1024;
        } else if (c == 'g' or c == 'G') {
            val = val * 1024 * 1024 * 1024;
        }
        i += 1;
    }
    return val;
}

fn parseU32(ptr: [*]const u8) u32 {
    var s = cstrToSlice(ptr);
    var val: u32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        var c = s[i];
        if (c >= '0' and c <= '9') {
            val = val * 10 + @intCast(u32, c - '0');
        }
        i += 1;
    }
    return val;
}

fn parseColorMode(ptr: [*]const u8) ColorMode {
    var s = cstrToSlice(ptr);
    const s_always: []const u8 = "always";
    const s_never: []const u8 = "never";
    if (matchFlag(s, s_always)) return ColorMode.always;
    if (matchFlag(s, s_never)) return ColorMode.never;
    return ColorMode.auto;
}

fn parseErrorFormat(ptr: [*]const u8) ErrorFormat {
    var s = cstrToSlice(ptr);
    const s_json: []const u8 = "json";
    const s_sarif: []const u8 = "sarif";
    if (matchFlag(s, s_json)) return ErrorFormat.json;
    if (matchFlag(s, s_sarif)) return ErrorFormat.sarif;
    return ErrorFormat.human;
}

fn printUsage() void {
    const msg: []const u8 = "zig1 - Z98 self-hosted compiler - usage: zig1 [options] <input.zig>\n";
    pal.stderr_write(msg);
}
