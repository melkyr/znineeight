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
const mr_mod = @import("module_registry.zig");
const ModuleRegistry = mr_mod.ModuleRegistry;
const import_resolver = @import("import_resolver.zig");
const az_mod = @import("analyzer.zig");
const sym_mod = @import("symbol_table.zig");
const type_mod = @import("type_registry.zig");
const TypeRegistry = type_mod.TypeRegistry;
const c89_mod = @import("c89_emit.zig");
const lower_mod = @import("lower.zig");
const SemanticContext = lower_mod.SemanticContext;
const LirLowerer = lower_mod.LirLowerer;
const lir_mod = @import("lir.zig");
const LirFunctionArrayList = lir_mod.LirFunctionArrayList;
const resolved_type_table = @import("resolved_type_table.zig");
const ResolvedTypeTable = resolved_type_table.ResolvedTypeTable;
const coercion_mod = @import("coercion.zig");
const CoercionTable = coercion_mod.CoercionTable;
const type_resolver = @import("type_resolver.zig");
const symbol_registrator = @import("symbol_registrator.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const AstKind = ast_mod.AstKind;
const AstStore = ast_mod.AstStore;
const LirFunction = @import("lir.zig").LirFunction;

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
    dump_types: bool,
    dump_lir: bool,
    dump_c89: bool,
    max_mem: u32,
    max_errors: u32,
    color: ColorMode,
    error_format: ErrorFormat,
    warnings_as_errors: bool,
    quiet: bool,
    test_mode: bool,
    sanity_test_mode: bool,
    track_memory: bool,
    no_null_check: bool,
    no_lifetime_check: bool,
    no_leak_check: bool,
    warn_all: bool,
    warn_error: bool,
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
    module_reg: *ModuleRegistry,
    typereg: *TypeRegistry,
    store: *AstStore,
    symbol_reg: *SymbolRegistry,
    resolved_types: *ResolvedTypeTable,
    coercion_table: *CoercionTable,
    lir_fns: LirFunctionArrayList,
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
    var mr = mr_mod.moduleRegistryInit(&perm_sand, &interner, &diag);
    var type_db_buf: [131072]u8 = undefined;
    var type_db = alloc_mod.sandInit(type_db_buf[0..]);
    var typereg = type_mod.typeRegistryInit(&type_db, &interner);
    type_mod.typeRegistryRegisterPrimitives(&typereg);
    var store = ast_mod.astStoreInit(&compiler_alloc.module);
    var symbol_reg = sym_mod.symbolRegistryInit(&perm_sand);
    var resolved_types = resolved_type_table.resolvedTypeTableInit(&compiler_alloc.module);
    var coercion_table = coercion_mod.coercionTableInit(&compiler_alloc.module);
    var lir_fns = lir_mod.lirFunctionArrayListInit(&compiler_alloc.module);
    var ctx = CompilerContext{
        .cli = cli,
        .alloc = &compiler_alloc,
        .interner = &interner,
        .diag = &diag,
        .source_man = &source_man,
        .name_mangler = &name_mangler,
        .module_reg = &mr,
        .typereg = &typereg,
        .store = &store,
        .symbol_reg = &symbol_reg,
        .resolved_types = &resolved_types,
        .coercion_table = &coercion_table,
        .lir_fns = lir_fns,
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
    phase_StaticAnalyzers(ctx);
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
    if ((ctx.cli.warnings_as_errors or ctx.cli.warn_error) and diag_mod.diagnosticCollectorWarningCount(ctx.diag) > 0) {
        pal.exit(1);
    }
    if (ctx.cli.track_memory) {
        var perm_kb: u32 = @intCast(u32, ctx.alloc.permanent.peak / @intCast(usize, 1024));
        var mod_kb: u32 = @intCast(u32, ctx.alloc.module.peak / @intCast(usize, 1024));
        var scr_kb: u32 = @intCast(u32, ctx.alloc.scratch.peak / @intCast(usize, 1024));
        var total: u32 = perm_kb + mod_kb + scr_kb;
        var msg1: []const u8 = "track-memory: perm=";
        pal.stderr_write(msg1);
        writeU32(perm_kb);
        var msg2: []const u8 = "K mod=";
        pal.stderr_write(msg2);
        writeU32(mod_kb);
        var msg3: []const u8 = "K scr=";
        pal.stderr_write(msg3);
        writeU32(scr_kb);
        var msg4: []const u8 = "K total=";
        pal.stderr_write(msg4);
        writeU32(total);
        var msg5: []const u8 = "K\n";
        pal.stderr_write(msg5);
    }
}

fn phase_ImportResolution(ctx: *CompilerContext) void {
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var path_id = interner_mod.stringInternerIntern(ctx.interner, ctx.cli.input_file);
    var mod_id = mr_mod.moduleRegistryAddModule(ctx.module_reg, path_id);
    mr_mod.importQueueEnqueue(&ctx.module_reg.import_queue, mod_id);
    import_resolver.moduleRegistryResolveImports(ctx.module_reg, &ctx.alloc.module, &ctx.alloc.scratch, ctx.store);
}

fn phase_SymbolRegistration(ctx: *CompilerContext) void {
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var dep_graph = symbol_registrator.depGraphInit(&ctx.alloc.scratch);
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        symbol_registrator.registerModuleSymbols(ctx.module_reg, ctx.symbol_reg, ctx.typereg, ctx.store, mods[mi].id, &dep_graph);
    }
}

fn phase_TypeResolution(ctx: *CompilerContext) void {
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var dep_graph = symbol_registrator.depGraphInit(&ctx.alloc.scratch);
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        symbol_registrator.registerModuleSymbols(ctx.module_reg, ctx.symbol_reg, ctx.typereg, ctx.store, mods[mi].id, &dep_graph);
    }
    var tr = type_resolver.typeResolverInit(ctx.typereg, ctx.diag, &ctx.alloc.scratch);
    type_resolver.typeResolverBuild(&tr, &dep_graph);
    type_resolver.typeResolverResolve(&tr);
}

fn phase_SemanticAnalysis(ctx: *CompilerContext) void {
    alloc_mod.sandReset(&ctx.alloc.scratch);
    _ = ctx;
}

fn phase_StaticAnalyzers(ctx: *CompilerContext) void {
    alloc_mod.sandReset(&ctx.alloc.scratch);
    alloc_mod.sandResetPeak(&ctx.alloc.scratch);
    if (ctx.cli.no_null_check != true or ctx.cli.no_lifetime_check != true or ctx.cli.no_leak_check != true) {
        var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
        var mi: usize = 0;
        while (mi < mods.len) : (mi += 1) {
            if (mods[mi].ast_root != @intCast(u32, 0)) {
                _ = mods[mi].ast_root;
            }
        }
    }
}

fn phase_LIRLowering(ctx: *CompilerContext) void {
    alloc_mod.sandReset(&ctx.alloc.scratch);
    ctx.lir_fns.len = @intCast(usize, 0);
    var sem_ctx = SemanticContext{
        .store = ctx.store,
        .registry = ctx.typereg,
        .symbol_tables = ctx.symbol_reg,
        .resolved_types = ctx.resolved_types,
        .coercions = ctx.coercion_table,
        .diag = ctx.diag,
    };
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        if (mods[mi].ast_root != @intCast(u32, 0)) {
            var root = ctx.store.nodes.items[@intCast(usize, mods[mi].ast_root)];
            if (root.kind == AstKind.module_root) {
                var decls = ast_mod.astStoreGetExtraChildren(ctx.store, root.payload);
                var di: usize = @intCast(usize, 0);
                while (di < decls.len) : (di += @intCast(usize, 1)) {
                    var decl = ctx.store.nodes.items[@intCast(usize, decls[di])];
                    if (decl.kind == AstKind.fn_decl) {
                        var lowerer = lower_mod.lowererInit(&sem_ctx, &ctx.alloc.scratch);
                        lowerer.module_id = mods[mi].id;
                        lowerer.module_reg = ctx.module_reg;
                        var lf = lower_mod.lowerFn(&lowerer, decls[di]);
                        lir_mod.lirFunctionArrayListAppend(&ctx.lir_fns, lf);
                    }
                }
            }
        }
    }
}

fn phase_C89Emission(ctx: *CompilerContext) void {
    if (!ctx.cli.dump_c89) return;
    var mangler: c89_mod.NameMangler = undefined;
    mangler = c89_mod.nameManglerInit(ctx.interner, &ctx.alloc.scratch);
    var emitter: c89_mod.C89Emitter = undefined;
    emitter = c89_mod.c89EmitterInit(
        ctx.typereg,
        ctx.interner,
        &mangler,
        ctx.diag,
        undefined,
        undefined,
        &ctx.alloc.scratch,
    );
    var fns = lir_mod.lirFunctionArrayListGetSlice(&ctx.lir_fns);
    var module_name: []const u8 = "output";

    var cwriter: c89_mod.BufferedWriter = undefined;
    cwriter = c89_mod.bufferedWriterInit();
    c89_mod.emitZigCompatH(&cwriter);
    c89_mod.bufferedWriterFlush(&cwriter);

    var swriter2: c89_mod.BufferedWriter = undefined;
    swriter2 = c89_mod.bufferedWriterInit();
    c89_mod.emitZigRuntimeC(&swriter2);
    c89_mod.bufferedWriterFlush(&swriter2);

    c89_mod.emitModule(&emitter, module_name, fns, @intCast(u32, 0));
    c89_mod.bufferedWriterFlush(&emitter.writer);

    var target_name: []const u8 = "target";
    var target_exe: []const u8 = "target.exe";

    var swriter: c89_mod.BufferedWriter = undefined;
    swriter = c89_mod.bufferedWriterInit();
    c89_mod.emitBuildTargetSh(&swriter, target_name);
    c89_mod.bufferedWriterFlush(&swriter);

    var bwriter: c89_mod.BufferedWriter = undefined;
    bwriter = c89_mod.bufferedWriterInit();
    c89_mod.emitBuildTargetBat(&bwriter, target_exe);
    c89_mod.bufferedWriterFlush(&bwriter);

    var owriter: c89_mod.BufferedWriter = undefined;
    owriter = c89_mod.bufferedWriterInit();
    c89_mod.emitBuildOwcBat(&owriter, target_exe);
    c89_mod.bufferedWriterFlush(&owriter);
}

fn parseArgs() CompilerCli {
    const empty_str: []const u8 = "";
    const dot_str: []const u8 = ".";
    var cli = CompilerCli{
        .input_file = empty_str,
        .output_dir = dot_str,
        .dump_types = false,
        .dump_lir = false,
        .dump_c89 = false,
        .max_mem = @intCast(u32, alloc_mod.DEV_MAX_MEM),
        .max_errors = @intCast(u32, 256),
        .color = ColorMode.auto,
        .error_format = ErrorFormat.human,
        .warnings_as_errors = false,
        .quiet = false,
        .test_mode = false,
        .sanity_test_mode = false,
        .track_memory = false,
        .no_null_check = false,
        .no_lifetime_check = false,
        .no_leak_check = false,
        .warn_all = false,
        .warn_error = false,
        .include_count = @intCast(u32, 0),
        .include_dirs = undefined,
    };
    var argc = pal.argCount();
    var i: i32 = 1;
    const s_dump_types: []const u8 = "--dump-types";
    const s_dump_lir: []const u8 = "--dump-lir";
    const s_dump_c89: []const u8 = "--dump-c89";
    const s_max_mem: []const u8 = "--max-mem";
    const s_max_errors: []const u8 = "--max-errors";
    const s_output_dir: []const u8 = "--output-dir";
    const s_quiet: []const u8 = "--quiet";
    const s_test: []const u8 = "--test";
    const s_sanity_test: []const u8 = "--sanity-test";
    const s_warnings: []const u8 = "--warnings-as-errors";
    const s_color: []const u8 = "--color";
    const s_error_format: []const u8 = "--error-format";
    const s_track_memory: []const u8 = "--track-memory";
    const s_no_null: []const u8 = "--no-null-check";
    const s_no_lifetime: []const u8 = "--no-lifetime-check";
    const s_no_leak: []const u8 = "--no-leak-check";
    const s_warn_all: []const u8 = "--warn-all";
    const s_warn_error: []const u8 = "--warn-error";
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
            if (matchFlag(arg, s_dump_types) or matchFlag(arg, s_y)) {
                cli.dump_types = true;
            } else if (matchFlag(arg, s_dump_lir) or matchFlag(arg, s_l)) {
                cli.dump_lir = true;
            } else if (matchFlag(arg, s_dump_c89)) {
                cli.dump_c89 = true;
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
            } else if (matchFlag(arg, s_sanity_test)) {
                cli.sanity_test_mode = true;
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
            } else if (matchFlag(arg, s_no_null)) {
                cli.no_null_check = true;
            } else if (matchFlag(arg, s_no_lifetime)) {
                cli.no_lifetime_check = true;
            } else if (matchFlag(arg, s_no_leak)) {
                cli.no_leak_check = true;
            } else if (matchFlag(arg, s_warn_all)) {
                cli.warn_all = true;
            } else if (matchFlag(arg, s_warn_error)) {
                cli.warnings_as_errors = true;
                cli.warn_error = true;
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

fn writeU32(val: usize) void {
    var buf: [16]u8 = undefined;
    var i: usize = 16;
    var v = val;
    if (v == 0) {
        buf[15] = 48;
        var s = buf[15..16];
        pal.stderr_write(s);
        return;
    }
    while (v > 0 and i > 0) {
        i -= 1;
        buf[i] = @intCast(u8, @intCast(u32, 48 + @intCast(u32, v % 10)));
        v = v / 10;
    }
    var s = buf[i..16];
    pal.stderr_write(s);
}

fn printUsage() void {
    const msg: []const u8 = "zig1 - Z98 self-hosted compiler - usage: zig1 [options] <input.zig>\n";
    pal.stderr_write(msg);
}
