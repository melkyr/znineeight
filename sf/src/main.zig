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
const itoa_mod = @import("util/itoa.zig");
const path_mod = @import("util/path.zig");
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
const hash_mod = @import("util/hash.zig");
const ResolvedTypeTable = resolved_type_table.ResolvedTypeTable;
const coercion_mod = @import("coercion.zig");
const CoercionTable = coercion_mod.CoercionTable;
const sa_mod = @import("semantic_analyzer.zig");
const type_resolver = @import("type_resolver.zig");
const ce_mod = @import("comptime_eval.zig");
const symbol_registrator = @import("symbol_registrator.zig");
const const_alias_prepass = @import("const_alias_prepass.zig");
const front_res = @import("front_resolution.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const AstKind = ast_mod.AstKind;
const AstStore = ast_mod.AstStore;
const LirFunction = @import("lir.zig").LirFunction;
const cinclude = @import("cinclude.zig");

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
    output_dir_set: bool,
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
     show_markers: bool,
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
    // KEPT (unwired) — cross-phase type dependency graph per TYPE_SYSTEM_p2.md §2.4. Currently not populated in pipeline; live DepGraphs are scratch-local per phase (see 09_pipeline_orchestration.md).
    dep_graph: *symbol_registrator.DepGraph,
    lir_fns: LirFunctionArrayList,
    enum_value_table: hash_mod.U32ToU32Map,
    error_code_registry: hash_mod.U32ToU32Map,
    call_arg_types: hash_mod.U32ToU32Map,
    call_param_map: hash_mod.U32ToU32Map,
    comptime_values: hash_mod.U32ToU64Map,
    pointer_only_ids: [*]u32,
    pointer_only_len: u32,
    global_decls: lir_mod.GlobalDeclArrayList,
};

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var startmsg: []const u8 = "START\n";
    pal.markerWrite(startmsg);
     var cli = parseArgs();
     if (cli.show_markers) { pal.markersEnabled(@intCast(u32, 1)); }
     if (cli.sanity_test_mode) {
        var compiler_alloc = alloc_mod.initCompilerAlloc();
         var interner = interner_mod.stringInternerInit(&compiler_alloc.permanent, 4);
         var source_man = sm_mod.sourceManagerInit(&compiler_alloc.permanent);
         var diag = diag_mod.diagnosticCollectorInit(&compiler_alloc.permanent, &source_man, &interner);
         token_mod.initKeywordTable(&compiler_alloc.permanent);

        lexer_mod.lexerTestSanityCheck();
        return;
    }
    if (cli.test_mode) {
        const msg: []const u8 = "error: use test_main.zig for test mode\n";
        pal.markerWrite(msg);
        pal.exit(1);
        return;
    }
    if (cli.input_file.len == 0) {
        printUsage();
        return;
    }
    var compiler_alloc = alloc_mod.initCompilerAlloc();
    compiler_alloc.max_mem = cli.max_mem;
    var source = pal.readFile(cli.input_file, &compiler_alloc.permanent) orelse {
        const msg: []const u8 = "error: could not read input file\n";
        pal.stderr_write(msg);
        pal.exit(@intCast(u8, 1));
        return;
    };
     var interner = interner_mod.stringInternerInit(&compiler_alloc.permanent, 4096);
     var source_man = sm_mod.sourceManagerInit(&compiler_alloc.permanent);
     var diag = diag_mod.diagnosticCollectorInit(&compiler_alloc.permanent, &source_man, &interner);
     diag.max_diagnostics = @intCast(usize, cli.max_errors);
     token_mod.initKeywordTable(&compiler_alloc.permanent);
     var name_mangler = nm_mod.nameManglerInit();
     var mr = mr_mod.moduleRegistryInit(&compiler_alloc.permanent, &interner, &diag);
     mr_mod.moduleRegistrySetSourceMan(&mr, &source_man);
     var type_db_arena: alloc_mod.GrowableSand = undefined;
     var type_db_name: []const u8 = "type_db";
     alloc_mod.growableSandInit(&type_db_arena, alloc_mod.poolPtr(), 4096, type_db_name);
     var typereg = type_mod.typeRegistryInit(&type_db_arena.view, &interner);
     type_mod.typeRegistryRegisterPrimitives(&typereg);
     var store = ast_mod.astStoreInit(&compiler_alloc.module);
     var symbol_reg = sym_mod.symbolRegistryInit(&compiler_alloc.permanent);
    var resolved_types = resolved_type_table.resolvedTypeTableInit(&compiler_alloc.module);
    var coercion_table = coercion_mod.coercionTableInit(&compiler_alloc.module);
    var lir_fns = lir_mod.lirFunctionArrayListInit(&compiler_alloc.module);
    var dep_graph = symbol_registrator.depGraphInit(&compiler_alloc.module);
    var enum_value_table = hash_mod.u32ToU32MapInit(&compiler_alloc.module);
    var error_code_registry = hash_mod.u32ToU32MapInit(&compiler_alloc.module);
     var call_arg_types = hash_mod.u32ToU32MapInit(&compiler_alloc.module);
     var call_param_map = hash_mod.u32ToU32MapInit(&compiler_alloc.module);
     var comptime_values = hash_mod.u32ToU64MapInit(&compiler_alloc.module);
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
        .dep_graph = &dep_graph,
        .lir_fns = lir_fns,
        .enum_value_table = enum_value_table,
        .error_code_registry = error_code_registry,
        .call_arg_types = call_arg_types,
        .call_param_map = call_param_map,
        .comptime_values = comptime_values,
        .pointer_only_ids = undefined,
        .pointer_only_len = @intCast(u32, 0),
        .global_decls = lir_mod.globalDeclArrayListInit(&compiler_alloc.module),
    };
    runCompiler(&ctx);
}

fn runCompiler(ctx: *CompilerContext) void {
    phase_ImportResolution(ctx);
    var z2: []const u8 = "2\n"; pal.markerWrite(z2);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    var z3: []const u8 = "3\n"; pal.markerWrite(z3);
    var z3a: []const u8 = "3a\n"; pal.markerWrite(z3a);
    var z4: []const u8 = "4\n"; pal.markerWrite(z4);
    phase_SymbolRegistration(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    phase_TypeResolution(ctx);
    var t1: []const u8 = "t1\n"; pal.markerWrite(t1);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    var t2: []const u8 = "t2\n"; pal.markerWrite(t2);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        diag_mod.diagnosticCollectorPrintAll(ctx.diag);
        pal.exit(2);
    }
    alloc_mod.checkCombinedPeak(ctx.alloc);
    phase_FrontResolution(ctx);
    phase_ComptimeEvaluation(ctx);
    phase_SemanticAnalysis(ctx);
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
    if ((ctx.cli.warnings_as_errors or ctx.cli.warn_error) and diag_mod.diagnosticCollectorWarningCount(ctx.diag) > 0) {
        diag_mod.diagnosticCollectorPrintAll(ctx.diag);
        pal.exit(1);
    }
    if (ctx.cli.track_memory) {
        var perm_kb: u32 = @intCast(u32, ctx.alloc.permanent.peak / @intCast(usize, 1024));
        var mod_kb: u32 = @intCast(u32, ctx.alloc.module.peak / @intCast(usize, 1024));
        var scr_kb: u32 = @intCast(u32, ctx.alloc.scratch.peak / @intCast(usize, 1024));
        var pool_kb: u32 = @intCast(u32, alloc_mod.poolPeak() / @intCast(usize, 1024));
        var type_db_kb: u32 = @intCast(u32, ctx.typereg.types_alloc.peak / @intCast(usize, 1024));
        var total: u32 = perm_kb + mod_kb + scr_kb;
        var msg1: []const u8 = "track-memory: perm=";
        pal.markerWrite(msg1);
        writeU32(perm_kb);
        var msg2: []const u8 = "K mod=";
        pal.markerWrite(msg2);
        writeU32(mod_kb);
        var msg3: []const u8 = "K scr=";
        pal.markerWrite(msg3);
        writeU32(scr_kb);
        var msg3b: []const u8 = "K pool=";
        pal.markerWrite(msg3b);
        writeU32(pool_kb);
        var msg3c: []const u8 = "K type_db=";
        pal.markerWrite(msg3c);
        writeU32(type_db_kb);
        var msg4: []const u8 = "K total=";
        pal.markerWrite(msg4);
        writeU32(total);
        var msg5: []const u8 = "K\n";
        pal.markerWrite(msg5);
    }
    diag_mod.diagnosticCollectorPrintAll(ctx.diag);
}

fn phase_ImportResolution(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "I\n"; pal.markerWrite(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var si: u32 = 0;
    while (si < ctx.cli.include_count) : (si += 1) {
        mr_mod.moduleResolverAddSearchDir(&ctx.module_reg.resolver, ctx.cli.include_dirs[@intCast(usize, si)]);
    }
    var lib_buf: [512]u8 = undefined;
    var lib_len = pal.getDefaultLibPath(&lib_buf[0], @intCast(i32, 512));
    if (lib_len > 0) {
        var lib_path = lib_buf[0..@intCast(usize, lib_len)];
        if (pal.fileExists(lib_path)) {
            mr_mod.moduleResolverAddSearchDir(&ctx.module_reg.resolver, lib_path);
        }
    }
    var root_buf: [512]u8 = undefined;
    var root_path = ctx.cli.input_file;
    if (ctx.cli.input_file.len <= 512) {
        var norm = path_mod.normalizePath(root_buf[0..ctx.cli.input_file.len], ctx.cli.input_file);
        if (norm) |n| root_path = n;
    }
    var path_id = interner_mod.stringInternerIntern(ctx.interner, root_path);
    var mod_id = mr_mod.moduleRegistryAddModule(ctx.module_reg, path_id);
    mr_mod.importQueueEnqueue(&ctx.module_reg.import_queue, mod_id);
    import_resolver.moduleRegistryResolveImports(ctx.module_reg, &ctx.alloc.module, &ctx.alloc.scratch, ctx.store);
    var z_msg: []const u8 = "Z\n"; pal.markerWrite(z_msg);
}

fn phase_SymbolRegistration(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "S\n"; pal.markerWrite(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var dep_graph = symbol_registrator.depGraphInit(&ctx.alloc.scratch);
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        symbol_registrator.registerModuleSymbols(ctx.module_reg, ctx.symbol_reg, ctx.typereg, ctx.store, mods[mi].id, &dep_graph, true);
    }
    var smods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    if (smods.len > @intCast(usize, 0) and smods[0].ast_root != @intCast(u32, 0)) {
        var sr = ctx.store.nodes.items[@intCast(usize, smods[0].ast_root)];
        if (sr.kind == AstKind.module_root) {
            var sdl = ast_mod.astStoreGetExtraChildren(ctx.store, sr.payload);
            var sdi: usize = @intCast(usize, 0);
            var sl: []const u8 = "S0"; pal.markerWrite(sl);
            while (sdi < sdl.len) : (sdi += @intCast(usize, 1)) {
                var sd = ctx.store.nodes.items[@intCast(usize, sdl[sdi])];
                var sk: u32 = @intCast(u32, @enumToInt(sd.kind));
                var sb: [20]u8 = undefined;
                var slen = itoa_mod.itoa(sk, sb[0..]);
                var sst: usize = @intCast(usize, 19) - @intCast(usize, slen);
                pal.markerWrite(sb[sst..@intCast(usize, 19)]);
                var ssp: []const u8 = " "; pal.markerWrite(ssp);
            }
            var sn: []const u8 = "\n"; pal.markerWrite(sn);
        }
    }
}

fn phase_TypeResolution(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "T\n"; pal.markerWrite(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var dep_graph = symbol_registrator.depGraphInit(&ctx.alloc.scratch);
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        symbol_registrator.registerModuleSymbols(ctx.module_reg, ctx.symbol_reg, ctx.typereg, ctx.store, mods[mi].id, &dep_graph, false);
    }
    const_alias_prepass.constAliasPrepass(ctx.symbol_reg, ctx.typereg, ctx.interner, ctx.store, &ctx.alloc.permanent);
    type_resolver.typeResolverResolveNames(ctx.store, ctx.typereg, ctx.symbol_reg, ctx.interner, ctx.resolved_types, ctx.module_reg, &ctx.alloc.permanent);
    var tr = type_resolver.typeResolverInit(ctx.typereg, ctx.diag, &ctx.alloc.scratch);
    type_resolver.typeResolverBuildDependencyGraph(&tr);
    type_resolver.typeResolverBuild(&tr, &dep_graph);
    type_resolver.typeResolverResolve(&tr);
    var ptr_grp = type_resolver.classifyTypeEmissionGroups(&tr, &ctx.alloc.permanent);
    ctx.pointer_only_ids = ptr_grp.ids;
    ctx.pointer_only_len = ptr_grp.len;
    if (mods.len > @intCast(usize, 0) and mods[0].ast_root != @intCast(u32, 0)) {
        var tr2 = ctx.store.nodes.items[@intCast(usize, mods[0].ast_root)];
        if (tr2.kind == AstKind.module_root) {
            var tdl = ast_mod.astStoreGetExtraChildren(ctx.store, tr2.payload);
            var tdi: usize = @intCast(usize, 0);
            var tl: []const u8 = "T0"; pal.markerWrite(tl);
            while (tdi < tdl.len) : (tdi += @intCast(usize, 1)) {
                var td = ctx.store.nodes.items[@intCast(usize, tdl[tdi])];
                var tk: u32 = @intCast(u32, @enumToInt(td.kind));
                var tb: [20]u8 = undefined;
                var tlen = itoa_mod.itoa(tk, tb[0..]);
                var tst: usize = @intCast(usize, 19) - @intCast(usize, tlen);
                pal.markerWrite(tb[tst..@intCast(usize, 19)]);
                var tsp: []const u8 = " "; pal.markerWrite(tsp);
            }
            var tn: []const u8 = "\n"; pal.markerWrite(tn);
        }
    }
}

fn phase_FrontResolution(ctx: *CompilerContext) void {
    var frc = front_res.FrontResCtx{
        .store = ctx.store,
        .typereg = ctx.typereg,
        .symbol_reg = ctx.symbol_reg,
        .resolved_types = ctx.resolved_types,
        .module_reg = ctx.module_reg,
        .interner = ctx.interner,
        .diag = ctx.diag,
        .scratch = &ctx.alloc.scratch,
        .coercion_table = ctx.coercion_table,
        .enum_value_table = &ctx.enum_value_table,
        .error_code_registry = &ctx.error_code_registry,
        .call_arg_types = &ctx.call_arg_types,
        .call_param_map = &ctx.call_param_map,
    };
    front_res.frontResolveModuleInits(&frc);
}

fn phase_ComptimeEvaluation(ctx: *CompilerContext) void {
    var pc_m: []const u8 = "CE\n"; pal.markerWrite(pc_m);
    var ce = ce_mod.comptimeEvalInit(ctx.typereg, ctx.store, ctx.interner, ctx.symbol_reg);
    var ni: usize = 0;
    while (ni < ctx.store.nodes.len) : (ni += @intCast(usize, 1)) {
        var node = ctx.store.nodes.items[ni];
        if (node.kind == AstKind.builtin_call) {
            var val = ce_mod.comptimeEvalEvaluate(&ce, @intCast(u32, ni));
            if (val) |v| {
                hash_mod.u32ToU64MapPut(&ctx.comptime_values, @intCast(u32, ni), v.bits);
            }
        } else if (node.kind == AstKind.var_decl and node.child_1 != 0) {
            if ((node.flags & @intCast(u8, 1)) == @intCast(u8, 0)) {
                var init_n = ctx.store.nodes.items[@intCast(usize, node.child_1)];
                var ik = @intCast(u32, @enumToInt(init_n.kind));
                if ((ik >= @intCast(u32, 33) and ik <= @intCast(u32, 42)) or
                    ik == @intCast(u32, 62) or ik == @intCast(u32, 64)) {
                    var val2 = ce_mod.comptimeEvalEvaluate(&ce, node.child_1);
                    if (val2) |v2| {
                        hash_mod.u32ToU64MapPut(&ctx.comptime_values, node.child_1, v2.bits);
                    }
                }
            }
        }
    }
}



fn phase_SemanticAnalysis(ctx: *CompilerContext) void {
    var rs: []const u8 = "RS"; pal.markerWrite(rs);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var frc = front_res.FrontResCtx{
        .store = ctx.store,
        .typereg = ctx.typereg,
        .symbol_reg = ctx.symbol_reg,
        .resolved_types = ctx.resolved_types,
        .module_reg = ctx.module_reg,
        .interner = ctx.interner,
        .diag = ctx.diag,
        .scratch = &ctx.alloc.scratch,
        .coercion_table = ctx.coercion_table,
        .enum_value_table = &ctx.enum_value_table,
        .error_code_registry = &ctx.error_code_registry,
        .call_arg_types = &ctx.call_arg_types,
        .call_param_map = &ctx.call_param_map,
    };
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        alloc_mod.sandReset(&ctx.alloc.scratch);
        var ast_root = mods[mi].ast_root;
        if (ast_root == @intCast(u32, 0)) { var mz: []const u8 = "MZ"; pal.markerWrite(mz); continue; }
        var root = ctx.store.nodes.items[@intCast(usize, ast_root)];
        var decls = ast_mod.astStoreGetExtraChildren(ctx.store, root.payload);
         var ad: []const u8 = "AD"; pal.markerWrite(ad);
         var dse_m: []const u8 = "DSE\n"; pal.markerWrite(dse_m);
         var src_fid = mods[mi].source_file_id;
         var sa = sa_mod.semanticAnalyzerInit(&ctx.alloc.scratch, ctx.resolved_types, ctx.diag, ctx.typereg, ctx.symbol_reg, ctx.store, mods[mi].id, src_fid, ctx.coercion_table, &ctx.enum_value_table, &ctx.error_code_registry, ctx.interner, &ctx.call_arg_types, &ctx.call_param_map);
        var di: usize = 0;
        while (di < decls.len) : (di += 1) {
            var decl = ctx.store.nodes.items[@intCast(usize, decls[di])];
            var dn: []const u8 = "DN"; pal.markerWrite(dn);
            if (decl.kind == AstKind.fn_decl) {
                if (decl.child_0 != 0) {
                    front_res.resolveStmtTypes(&frc, mods[mi].id, decl.child_0, @intCast(u32, 0));
                }
                var sa0: []const u8 = "SA"; pal.markerWrite(sa0);
                sa_mod.semanticAnalyzerResolveFnBody(&sa, decls[di]);
                var sa1: []const u8 = "sA"; pal.markerWrite(sa1);
            }
        }
    }

}




fn phase_StaticAnalyzers(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "A\n"; pal.markerWrite(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    alloc_mod.sandResetPeak(&ctx.alloc.scratch);
    if (ctx.cli.no_null_check != true or ctx.cli.no_lifetime_check != true or ctx.cli.no_leak_check != true) {
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
        while (mi < mods.len) : (mi += 1) {
            alloc_mod.sandReset(&ctx.alloc.scratch);
            var ast_root = mods[mi].ast_root;
            if (ast_root == @intCast(u32, 0)) continue;
            var sym_table = sym_mod.symbolRegistryGetTable(ctx.symbol_reg, @intCast(u32, mi));
            var ac = az_mod.AnalyzerContext{
                .store             = ctx.store,
                .registry          = ctx.typereg,
                .interner          = ctx.interner,
                .diag              = ctx.diag,
                .symbols           = sym_table,
                .alloc             = &ctx.alloc.scratch,
                .current_fn_name   = @intCast(u32, 0),
                .defer_queue_items = undefined,
                .defer_queue_len   = @intCast(usize, 0),
                .defer_queue_cap   = @intCast(usize, 0),
                .defer_queue_alloc = &ctx.alloc.scratch,
                .current_depth     = @intCast(u32, 0),
                .null_analysis_mode    = @intCast(u8, 0),
                .skip_null_check       = @intCast(u8, if (ctx.cli.no_null_check) 1 else 0),
                .skip_lifetime_check   = @intCast(u8, if (ctx.cli.no_lifetime_check) 1 else 0),
                .skip_doublefree_check = @intCast(u8, if (ctx.cli.no_leak_check) 1 else 0),
                .warn_all          = @intCast(u8, if (ctx.cli.warn_all) 1 else 0),
                .on_stmt_cb = az_mod.onNullStmt,
                .in_defer_exec = @intCast(u8, 0),
                .lifetime_analysis_mode = @intCast(u8, 0),
                .doublefree_analysis_mode = @intCast(u8, 0),
            };
            az_mod.runAllAnalyzers(&ac, ast_root);
        }
    }
}

fn phase_LIRLowering(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "L\n"; pal.markerWrite(p_msg);
    var lnmsg: []const u8 = "nodes="; pal.markerWrite(lnmsg);
    var ln_buf: [20]u8 = undefined;
    var ln_len = itoa_mod.itoa(@intCast(u32, ctx.store.nodes.len), ln_buf[0..]);
    var ln_start: usize = @intCast(usize, 19) - @intCast(usize, ln_len);
    pal.markerWrite(ln_buf[ln_start..@intCast(usize, 19)]);
    var lemsg: []const u8 = " extra="; pal.markerWrite(lemsg);
    var le_buf: [20]u8 = undefined;
    var le_len = itoa_mod.itoa(@intCast(u32, ctx.store.extra_children.len), le_buf[0..]);
    var le_start: usize = @intCast(usize, 19) - @intCast(usize, le_len);
    pal.markerWrite(le_buf[le_start..@intCast(usize, 19)]);
    var lnl: []const u8 = "\n"; pal.markerWrite(lnl);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    ctx.lir_fns.len = @intCast(usize, 0);
    var sem_ctx: SemanticContext = SemanticContext{
        .store = ctx.store,
        .registry = ctx.typereg,
        .symbol_tables = ctx.symbol_reg,
        .resolved_types = ctx.resolved_types,
        .coercions = ctx.coercion_table,
        .diag = ctx.diag,
        .has_symbols = @intCast(u8, 1),
        .enum_value_table = &ctx.enum_value_table,
        .error_code_registry = &ctx.error_code_registry,
        .call_arg_types = &ctx.call_arg_types,
        .comptime_values = &ctx.comptime_values,
        .source_file_id = @intCast(u32, 0),
    };
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        sem_ctx.source_file_id = mods[mi].source_file_id;
        var mm: []const u8 = "M"; pal.markerWrite(mm);
        var mi_buf: [20]u8 = undefined;
        var mi_len = itoa_mod.itoa(@intCast(u32, mi), mi_buf[0..]);
        var mi2_start: usize = @intCast(usize, 19) - @intCast(usize, mi_len);
        pal.markerWrite(mi_buf[mi2_start..@intCast(usize, 19)]);
        var msep: []const u8 = ":"; pal.markerWrite(msep);
        if (mods[mi].ast_root != @intCast(u32, 0)) {
            var ar_buf: [20]u8 = undefined;
            var ar_len = itoa_mod.itoa(mods[mi].ast_root, ar_buf[0..]);
            var ar_start: usize = @intCast(usize, 19) - @intCast(usize, ar_len);
            pal.markerWrite(ar_buf[ar_start..@intCast(usize, 19)]);
            pal.markerWrite(msep);
            var root = ctx.store.nodes.items[@intCast(usize, mods[mi].ast_root)];
            if (root.kind == AstKind.module_root) {
                var mr: []const u8 = "R"; pal.markerWrite(mr);
                var decls = ast_mod.astStoreGetExtraChildren(ctx.store, root.payload);
                var decl_len: u32 = @intCast(u32, decls.len);
                var dcount_buf: [20]u8 = undefined;
                var dcount_len = itoa_mod.itoa(decl_len, dcount_buf[0..]);
                var dstart: usize = @intCast(usize, 19) - @intCast(usize, dcount_len);
                pal.markerWrite(dcount_buf[dstart..@intCast(usize, 19)]);
                pal.markerWrite(msep);
                mr_mod.moduleRegistryCollectIncludes(ctx.store, decls, &mods[mi].c_includes);
                var mod_has_ri: u8 = @intCast(u8, 0);
                var di: usize = @intCast(usize, 0);
                while (di < decls.len) : (di += @intCast(usize, 1)) {
                    var decl = ctx.store.nodes.items[@intCast(usize, decls[di])];
                    var raw_k: u32 = @intCast(u32, @enumToInt(decl.kind));
                    var rbuf: [20]u8 = undefined;
                    var rlen = itoa_mod.itoa(raw_k, rbuf[0..]);
                    var rstart: usize = @intCast(usize, 19) - @intCast(usize, rlen);
                    pal.markerWrite(rbuf[rstart..@intCast(usize, 19)]);
                    var sp2: []const u8 = " ";
                    pal.markerWrite(sp2);
            if (decl.kind == AstKind.fn_decl) {
                        var mf: []const u8 = "F"; pal.markerWrite(mf);
                        var lowerer = lower_mod.lowererInit(&sem_ctx, &ctx.alloc.scratch);
                        lowerer.module_id = mods[mi].id;
                        lowerer.module_reg = ctx.module_reg;
                        var lf = lower_mod.lowerFn(&lowerer, decls[di]);
                        var lf_mod = lir_mod.lirFunctionRelocateToModule(lf, &ctx.alloc.module);
                        lir_mod.lirFunctionArrayListAppend(&ctx.lir_fns, lf_mod);
                        alloc_mod.sandReset(&ctx.alloc.scratch);
                    } else {
                if (decl.kind == AstKind.var_decl) {
                    if ((@intCast(u16, decl.flags) & @intCast(u16, 0x04)) == @intCast(u16, 0)) {
                        var gv_name: u32 = @intCast(u32, decl.payload);
                        var gv_sym = sym_mod.symbolRegistryQualifiedLookup(ctx.symbol_reg, mods[mi].id, gv_name);
                        if (gv_sym) |gvs| {
                            if (gvs.kind == sym_mod.SymbolKind.global) {
                                var gv_is_storage: u8 = @intCast(u8, 0);
                                if ((@intCast(u16, decl.flags) & @intCast(u16, 0x01)) != @intCast(u16, 0)) {
                                    gv_is_storage = @intCast(u8, 1);
                                } else if (decl.child_1 != @intCast(u32, 0)) {
                                    var gv_init = ctx.store.nodes.items[@intCast(usize, decl.child_1)];
                                    if (gv_init.kind != AstKind.int_literal and gv_init.kind != AstKind.float_literal and gv_init.kind != AstKind.char_literal) {
                                        gv_is_storage = @intCast(u8, 1);
                                    }
                                }
                                if (gv_is_storage == @intCast(u8, 1)) {
                                    if (decl.child_1 != @intCast(u32, 0)) {
                                        var gv_init3 = ctx.store.nodes.items[@intCast(usize, decl.child_1)];
                                        if (gv_init3.kind == AstKind.import_expr) { gv_is_storage = @intCast(u8, 0); }
                                        if (gv_init3.kind == AstKind.field_access) {
                                            var gv_fb = ctx.store.nodes.items[@intCast(usize, gv_init3.child_0)];
                                            if (gv_fb.kind == AstKind.import_expr) { gv_is_storage = @intCast(u8, 0); }
                                        }
                                    }
                                }
                                if (gv_is_storage == @intCast(u8, 1)) {
                                    var gv_has_ri: u8 = @intCast(u8, 0);
                                    if (decl.child_1 != @intCast(u32, 0)) {
                                        var gv_init2 = ctx.store.nodes.items[@intCast(usize, decl.child_1)];
                                        if (gv_init2.kind != AstKind.undefined_literal) { gv_has_ri = @intCast(u8, 1); }
                                    }
                                    if (gv_has_ri == @intCast(u8, 1)) { mod_has_ri = @intCast(u8, 1); }
                                    var gv_rt = resolved_type_table.resolvedTypeTableGet(ctx.resolved_types, decls[di]);
                                    var gv_tid: u32 = if (gv_rt) |grt| grt else type_mod.TYPE_UNDEFINED;
                                    lir_mod.globalDeclArrayListAppend(&ctx.global_decls, lir_mod.ModuleGlobalDecl{
                                        .name_id = gv_name,
                                        .module_id = mods[mi].id,
                                        .type_id = gv_tid,
                                        .has_runtime_init = gv_has_ri,
                                    });
                                }
                            }
                        }
                    }
                }
        }
    }
    if (mod_has_ri != @intCast(u8, 0)) {
        var ilowerer = lower_mod.lowererInit(&sem_ctx, &ctx.alloc.scratch);
        ilowerer.module_id = mods[mi].id;
        ilowerer.module_reg = ctx.module_reg;
        var imf = lower_mod.lowerModuleInit(&ilowerer, decls, mods[mi].id);
        var imf_mod = lir_mod.lirFunctionRelocateToModule(imf, &ctx.alloc.module);
        lir_mod.lirFunctionArrayListAppend(&ctx.lir_fns, imf_mod);
        alloc_mod.sandReset(&ctx.alloc.scratch);
    }
    var amods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    if (amods.len > @intCast(usize, 0) and amods[0].ast_root != @intCast(u32, 0)) {
        var ar = ctx.store.nodes.items[@intCast(usize, amods[0].ast_root)];
        if (ar.kind == AstKind.module_root) {
            var adl = ast_mod.astStoreGetExtraChildren(ctx.store, ar.payload);
            var adi: usize = @intCast(usize, 0);
            var al: []const u8 = "A0"; pal.markerWrite(al);
            while (adi < adl.len) : (adi += @intCast(usize, 1)) {
                var ad = ctx.store.nodes.items[@intCast(usize, adl[adi])];
                var ak: u32 = @intCast(u32, @enumToInt(ad.kind));
                var ab: [20]u8 = undefined;
                var alen = itoa_mod.itoa(ak, ab[0..]);
                var ast: usize = @intCast(usize, 19) - @intCast(usize, alen);
                pal.markerWrite(ab[ast..@intCast(usize, 19)]);
                var asp: []const u8 = " "; pal.markerWrite(asp);
            }
            var an: []const u8 = "\n"; pal.markerWrite(an);
        }
    }
}
        }
    }
}

fn errorCodeRegistryFinalize(ctx: *CompilerContext) void {
    var ti: usize = 0;
    while (ti < ctx.typereg.types_len) : (ti += 1) {
        var ty = ctx.typereg.types_items[ti];
        if (ty.kind != type_mod.TypeKind.error_set_type) continue;
        if (@intCast(usize, ty.payload_idx) >= ctx.typereg.es_len) continue;
        var esp = ctx.typereg.es_items[@intCast(usize, ty.payload_idx)];
        var ei: usize = 0;
        while (ei < @intCast(usize, esp.tags_count)) : (ei += 1) {
            var mname_id = ctx.typereg.xn_items[@intCast(usize, esp.tags_start) + ei];
            _ = hash_mod.u32ToU32MapGetOrAddDense(&ctx.error_code_registry, mname_id);
        }
    }
}

fn phase_C89Emission(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "C\n"; pal.markerWrite(p_msg);
    if (!ctx.cli.dump_c89) return;
    var mangler: c89_mod.NameMangler = undefined;
    var mangler_hint: usize = ctx.lir_fns.len + ctx.global_decls.len + @intCast(usize, ctx.pointer_only_len) + @intCast(usize, 32);
    mangler = c89_mod.nameManglerInit(ctx.interner, &ctx.alloc.scratch, mangler_hint);
    var emitter: c89_mod.C89Emitter = undefined;
    emitter = c89_mod.c89EmitterInit(
        ctx.typereg,
        ctx.interner,
        &mangler,
        ctx.diag,
        undefined,
        undefined,
        &ctx.alloc.scratch,
        &ctx.error_code_registry,
        ctx.pointer_only_len,
    );
    emitter.module_reg = ctx.module_reg;
    errorCodeRegistryFinalize(ctx);
    var gd_slice = lir_mod.globalDeclArrayListGetSlice(&ctx.global_decls);
    emitter.global_decls = gd_slice.ptr;
    emitter.global_decls_len = @intCast(u32, gd_slice.len);
    var fns = lir_mod.lirFunctionArrayListGetSlice(&ctx.lir_fns);
    var module_name: []const u8 = "output";

    if (ctx.cli.output_dir_set) {
        var poi: u32 = @intCast(u32, 0);
        while (poi < ctx.pointer_only_len) : (poi += 1) {
            hash_mod.u32ToU32MapPut(&emitter.pointer_only_map, ctx.pointer_only_ids[@intCast(usize, poi)], @intCast(u32, 1));
        }
        var sorted: [*]u32 = c89_mod.tstTopologicalSort(ctx.typereg, &ctx.alloc.scratch);
        var hpath: [512]u8 = undefined;
        var hp: usize = @intCast(usize, 0);
        var od = ctx.cli.output_dir;
        var hi: usize = @intCast(usize, 0);
        while (hi < od.len and hp < @intCast(usize, 510)) : (hi += 1) { hpath[hp] = od[hi]; hp += 1; }
        hpath[hp] = @intCast(u8, '/'); hp += 1;
        var hfn: []const u8 = "zig_special_types.h";
        var hfi: usize = @intCast(usize, 0);
        while (hfi < hfn.len and hp < @intCast(usize, 511)) : (hfi += 1) { hpath[hp] = hfn[hfi]; hp += 1; }
        var fd: usize = pal.fileOpen(hpath[0..hp], @intCast(i32, 0));
        if (fd == pal.INVALID_FD) {
            var emsg: []const u8 = "error: cannot open output file\n";
            pal.stderr_write(emsg);
            pal.exit(@intCast(u8, 1));
        }
        var hw: c89_mod.BufferedWriter = undefined;
        hw = c89_mod.bufferedWriterInitFd(fd);
        emitter.writer = hw;
        c89_mod.emitSharedHeader(&emitter, ctx.typereg, sorted);
        c89_mod.bufferedWriterFlush(&emitter.writer);
        pal.fileClose(fd);
        var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
        var fn_cursor: usize = @intCast(usize, 0);
        var mi: usize = @intCast(usize, 0);
        while (mi < mods.len) : (mi += 1) {
            var m = mods[mi];
            var fn_start: usize = fn_cursor;
            while (fn_cursor < fns.len and fns[fn_cursor].module_id == m.id) : (fn_cursor += @intCast(usize, 1)) {}
            var fn_slice = fns[fn_start..fn_cursor];
            var base = c89_mod.moduleQualifiedName(&emitter, m.id);
            if (od.len + @intCast(usize, 1) + base.len + @intCast(usize, 3) > @intCast(usize, 511)) {
                var lmsg: []const u8 = "error: output filename too long\n";
                pal.stderr_write(lmsg);
                pal.exit(@intCast(u8, 1));
            }
            var hp2: usize = @intCast(usize, 0);
            var hi2: usize = @intCast(usize, 0);
            while (hi2 < od.len and hp2 < @intCast(usize, 510)) : (hi2 += 1) { hpath[hp2] = od[hi2]; hp2 += 1; }
            hpath[hp2] = @intCast(u8, '/'); hp2 += 1;
            var bi: usize = @intCast(usize, 0);
            while (bi < base.len and hp2 < @intCast(usize, 510)) : (bi += 1) { hpath[hp2] = base[bi]; hp2 += 1; }
            var hext: []const u8 = ".h";
            var hx: usize = @intCast(usize, 0);
            while (hx < hext.len and hp2 < @intCast(usize, 511)) : (hx += 1) { hpath[hp2] = hext[hx]; hp2 += 1; }
            var fd2: usize = pal.fileOpen(hpath[0..hp2], @intCast(i32, 0));
            if (fd2 == pal.INVALID_FD) {
                var emsg2: []const u8 = "error: cannot open output file\n";
                pal.stderr_write(emsg2);
                pal.exit(@intCast(u8, 1));
            }
            var hw2: c89_mod.BufferedWriter = undefined;
            hw2 = c89_mod.bufferedWriterInitFd(fd2);
            emitter.writer = hw2;
            var dep_start: usize = @intCast(usize, m.imports_start);
            var dep_end: usize = dep_start + @intCast(usize, m.import_count);
            var dep_ids = ctx.module_reg.import_edges_items[dep_start..dep_end];
            var m_c_incs = m.c_includes.items[0..m.c_includes.len];
            c89_mod.emitModuleHeaderFile(&emitter, m.id, base, fn_slice, m_c_incs, dep_ids, sorted);
            c89_mod.bufferedWriterFlush(&emitter.writer);
            pal.fileClose(fd2);
            var ff_m: []const u8 = "FINAL_FLUSH\n"; pal.markerWrite(ff_m);
            var cpath: [512]u8 = undefined;
            var cp2: usize = @intCast(usize, 0);
            var ci2: usize = @intCast(usize, 0);
            while (ci2 < od.len and cp2 < @intCast(usize, 510)) : (ci2 += 1) { cpath[cp2] = od[ci2]; cp2 += 1; }
            cpath[cp2] = @intCast(u8, '/'); cp2 += 1;
            var cbi: usize = @intCast(usize, 0);
            while (cbi < base.len and cp2 < @intCast(usize, 510)) : (cbi += 1) { cpath[cp2] = base[cbi]; cp2 += 1; }
            var cext: []const u8 = ".c";
            var cx: usize = @intCast(usize, 0);
            while (cx < cext.len and cp2 < @intCast(usize, 511)) : (cx += 1) { cpath[cp2] = cext[cx]; cp2 += 1; }
            var cfd: usize = pal.fileOpen(cpath[0..cp2], @intCast(i32, 0));
            if (cfd == pal.INVALID_FD) {
                var emsg3: []const u8 = "error: cannot open output file\n";
                pal.stderr_write(emsg3);
                pal.exit(@intCast(u8, 1));
            }
            var cw: c89_mod.BufferedWriter = undefined;
            cw = c89_mod.bufferedWriterInitFd(cfd);
            emitter.writer = cw;
            c89_mod.emitModuleFile(&emitter, m.id, base, fn_slice);
            c89_mod.bufferedWriterFlush(&emitter.writer);
            pal.fileClose(cfd);
            var ff2_m: []const u8 = "FINAL_FLUSH\n"; pal.markerWrite(ff2_m);
        }
        return;
    }

    var cwriter: c89_mod.BufferedWriter = undefined;
    cwriter = c89_mod.bufferedWriterInit();
    c89_mod.emitIncludes(&cwriter);
    c89_mod.bufferedWriterFlush(&cwriter);

    var c_incs = cinclude.cincludeUnionAll(ctx.module_reg, &ctx.alloc.scratch);
    c89_mod.emitModule(&emitter, module_name, fns, c_incs, ctx.pointer_only_ids, ctx.pointer_only_len);
    var ff_m: []const u8 = "FINAL_FLUSH\n"; pal.markerWrite(ff_m);
    c89_mod.bufferedWriterFlush(&emitter.writer);
}

fn parseArgs() CompilerCli {
    const empty_str: []const u8 = "";
    const dot_str: []const u8 = ".";
    var cli = CompilerCli{
        .input_file = empty_str,
        .output_dir = dot_str,
        .output_dir_set = false,
        .dump_types = false,
        .dump_lir = false,
        .dump_c89 = false,
        .max_mem = @intCast(u32, alloc_mod.RELEASE_MAX_MEM),
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
         .show_markers = false,
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
     const s_markers: []const u8 = "--markers";
     const s_include: []const u8 = "-I";
    const s_lib_dir: []const u8 = "--lib-dir";
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
            if (matchFlag(arg, s_dump_c89)) {
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
                    cli.output_dir_set = true;
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
             } else if (matchFlag(arg, s_markers)) {
                 cli.show_markers = true;
             } else if (matchFlag(arg, s_include) or matchFlag(arg, s_lib_dir)) {
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
        pal.markerWrite(s);
        return;
    }
    while (v > 0 and i > 0) {
        i -= 1;
        buf[i] = @intCast(u8, @intCast(u32, 48 + @intCast(u32, v % 10)));
        v = v / 10;
    }
    var s = buf[i..16];
    pal.markerWrite(s);
}

fn printUsage() void {
    const msg: []const u8 = "zig1 - Z98 self-hosted compiler - usage: zig1 [options] <input.zig>\n";
    pal.markerWrite(msg);
}
