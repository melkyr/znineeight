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
    dep_graph: *symbol_registrator.DepGraph,
    lir_fns: LirFunctionArrayList,
    enum_value_table: hash_mod.U32ToU32Map,
};

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var startmsg: []const u8 = "START\n";
    pal.stderr_write(startmsg);
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
    var dep_graph = symbol_registrator.depGraphInit(&compiler_alloc.module);
    var enum_value_table = hash_mod.u32ToU32MapInit(&compiler_alloc.module);
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
    };
    runCompiler(&ctx);
}

fn runCompiler(ctx: *CompilerContext) void {
    phase_ImportResolution(ctx);
    var z2: []const u8 = "2\n"; pal.stderr_write(z2);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    var z3: []const u8 = "3\n"; pal.stderr_write(z3);
    var z3a: []const u8 = "3a\n"; pal.stderr_write(z3a);
    var z4: []const u8 = "4\n"; pal.stderr_write(z4);
    phase_SymbolRegistration(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    phase_TypeResolution(ctx);
    var t1: []const u8 = "t1\n"; pal.stderr_write(t1);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    var t2: []const u8 = "t2\n"; pal.stderr_write(t2);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        pal.exit(2);
    }
    phase_SemanticAnalysis(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        pal.exit(2);
    }
    phase_StaticAnalyzers(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        pal.exit(2);
    }
    phase_LIRLowering(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
    if (diag_mod.diagnosticCollectorHasErrors(ctx.diag)) {
        pal.exit(2);
    }
    phase_C89Emission(ctx);
    alloc_mod.checkCombinedPeak(ctx.alloc);
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
    var p_msg: []const u8 = "I\n"; pal.stderr_write(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var path_id = interner_mod.stringInternerIntern(ctx.interner, ctx.cli.input_file);
    var mod_id = mr_mod.moduleRegistryAddModule(ctx.module_reg, path_id);
    mr_mod.importQueueEnqueue(&ctx.module_reg.import_queue, mod_id);
    import_resolver.moduleRegistryResolveImports(ctx.module_reg, &ctx.alloc.module, &ctx.alloc.scratch, ctx.store);
    var z_msg: []const u8 = "Z\n"; pal.stderr_write(z_msg);
}

fn phase_SymbolRegistration(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "S\n"; pal.stderr_write(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var dep_graph = symbol_registrator.depGraphInit(&ctx.alloc.scratch);
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        symbol_registrator.registerModuleSymbols(ctx.module_reg, ctx.symbol_reg, ctx.typereg, ctx.store, mods[mi].id, &dep_graph);
    }
    var smods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    if (smods.len > @intCast(usize, 0) and smods[0].ast_root != @intCast(u32, 0)) {
        var sr = ctx.store.nodes.items[@intCast(usize, smods[0].ast_root)];
        if (sr.kind == AstKind.module_root) {
            var sdl = ast_mod.astStoreGetExtraChildren(ctx.store, sr.payload);
            var sdi: usize = @intCast(usize, 0);
            var sl: []const u8 = "S0"; pal.stderr_write(sl);
            while (sdi < sdl.len) : (sdi += @intCast(usize, 1)) {
                var sd = ctx.store.nodes.items[@intCast(usize, sdl[sdi])];
                var sk: u32 = @intCast(u32, @enumToInt(sd.kind));
                var sb: [20]u8 = undefined;
                var slen = itoa_mod.itoa(sk, sb[0..]);
                var sst: usize = @intCast(usize, 19) - @intCast(usize, slen);
                pal.stderr_write(sb[sst..@intCast(usize, 19)]);
                var ssp: []const u8 = " "; pal.stderr_write(ssp);
            }
            var sn: []const u8 = "\n"; pal.stderr_write(sn);
        }
    }
}

fn phase_TypeResolution(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "T\n"; pal.stderr_write(p_msg);
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
    if (mods.len > @intCast(usize, 0) and mods[0].ast_root != @intCast(u32, 0)) {
        var tr2 = ctx.store.nodes.items[@intCast(usize, mods[0].ast_root)];
        if (tr2.kind == AstKind.module_root) {
            var tdl = ast_mod.astStoreGetExtraChildren(ctx.store, tr2.payload);
            var tdi: usize = @intCast(usize, 0);
            var tl: []const u8 = "T0"; pal.stderr_write(tl);
            while (tdi < tdl.len) : (tdi += @intCast(usize, 1)) {
                var td = ctx.store.nodes.items[@intCast(usize, tdl[tdi])];
                var tk: u32 = @intCast(u32, @enumToInt(td.kind));
                var tb: [20]u8 = undefined;
                var tlen = itoa_mod.itoa(tk, tb[0..]);
                var tst: usize = @intCast(usize, 19) - @intCast(usize, tlen);
                pal.stderr_write(tb[tst..@intCast(usize, 19)]);
                var tsp: []const u8 = " "; pal.stderr_write(tsp);
            }
            var tn: []const u8 = "\n"; pal.stderr_write(tn);
        }
    }
}

fn phase_SemanticAnalysis(ctx: *CompilerContext) void {
    var rs: []const u8 = "RS"; pal.stderr_write(rs);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var ast_root = mods[mi].ast_root;
        if (ast_root == @intCast(u32, 0)) { var mz: []const u8 = "MZ"; pal.stderr_write(mz); continue; }
        var root = ctx.store.nodes.items[@intCast(usize, ast_root)];
        var decls = ast_mod.astStoreGetExtraChildren(ctx.store, root.payload);
        var ad: []const u8 = "AD"; pal.stderr_write(ad);
        var sa = sa_mod.semanticAnalyzerInit(&ctx.alloc.scratch, ctx.resolved_types, ctx.diag, ctx.typereg, ctx.symbol_reg, ctx.store, mods[mi].id, ctx.coercion_table, &ctx.enum_value_table, ctx.interner);
        var di: usize = 0;
        while (di < decls.len) : (di += 1) {
            var decl = ctx.store.nodes.items[@intCast(usize, decls[di])];
            var dn: []const u8 = "DN"; pal.stderr_write(dn);
            if (decl.kind == AstKind.fn_decl) {
                var proto = ctx.store.fn_protos.items[@intCast(usize, decl.payload)];
                var rt_box: [1]u32 = [1]u32{type_mod.TYPE_VOID};
                if (proto.return_type_node != 0) {
                    var rtype = resolveTypeExpr(ctx, proto.return_type_node);
                    if (rtype != type_mod.TYPE_UNDEFINED) {
                        rt_box[0] = rtype;
                        resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, proto.return_type_node, rtype);
                        var rt_ok: []const u8 = "T"; pal.stderr_write(rt_ok);
                    } else {
                        var rt_nok: []const u8 = "U"; pal.stderr_write(rt_nok);
                    }
                }
                var u1b_m: []const u8 = "U1b:c"; pal.stderr_write(u1b_m);
                var u1b_c: [20]u8 = undefined; var u1b_cl = itoa_mod.itoa(@intCast(u32, proto.params_count), u1b_c[0..]); var u1b_cs: usize = @intCast(usize, 19) - @intCast(usize, u1b_cl); pal.stderr_write(u1b_c[u1b_cs..@intCast(usize, 19)]);
                var u1b_sm: []const u8 = "s"; pal.stderr_write(u1b_sm);
                var u1b_s: [20]u8 = undefined; var u1b_sl = itoa_mod.itoa(@intCast(u32, proto.params_start), u1b_s[0..]); var u1b_ss: usize = @intCast(usize, 19) - @intCast(usize, u1b_sl); pal.stderr_write(u1b_s[u1b_ss..@intCast(usize, 19)]);
                if (proto.params_count > @intCast(u16, 0)) {
                    var p_payload = (@intCast(u32, proto.params_start) << @intCast(u32, 16)) | @intCast(u32, proto.params_count);
                    var fn_start: u16 = @intCast(u16, ctx.typereg.xt_len);
                    var pnodes = ast_mod.astStoreGetExtraChildren(ctx.store, p_payload);
                    var pi: usize = 0;
                    while (pi < pnodes.len) : (pi += 1) {
                        var pnode = ctx.store.nodes.items[@intCast(usize, pnodes[pi])];
                        if (pnode.child_0 != 0) {
                            var ptype = resolveTypeExpr(ctx, pnode.child_0);
                            var u1_m: []const u8 = "U1:"; pal.stderr_write(u1_m);
                            var u1_pb: [20]u8 = undefined; var u1_pl = itoa_mod.itoa(@intCast(u32, pi), u1_pb[0..]); var u1_ps: usize = @intCast(usize, 19) - @intCast(usize, u1_pl); pal.stderr_write(u1_pb[u1_ps..@intCast(usize, 19)]);
                            var u1_tm: []const u8 = "t"; pal.stderr_write(u1_tm);
                            var u1_tb: [20]u8 = undefined; var u1_tl = itoa_mod.itoa(ptype, u1_tb[0..]); var u1_ts: usize = @intCast(usize, 19) - @intCast(usize, u1_tl); pal.stderr_write(u1_tb[u1_ts..@intCast(usize, 19)]);
                            type_mod.xtAppend(ctx.typereg, ptype);
                            if (ptype != type_mod.TYPE_UNDEFINED) {
                                resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, pnode.child_0, ptype);
                            }
                        } else {
                            type_mod.xtAppend(ctx.typereg, type_mod.TYPE_VOID);
                        }
                    }
                    var zz0_tid = type_mod.typeRegistryGetOrCreateFn(ctx.typereg, proto.name_id, fn_start, proto.params_count, rt_box[0]);
                    resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, decls[di], zz0_tid);
                }
                if (decl.child_0 != 0) {
                    resolveStmtTypes(ctx, decl.child_0, @intCast(u32, 0));
                }
                var sa0: []const u8 = "SA"; pal.stderr_write(sa0);
                sa_mod.semanticAnalyzerResolveFnBody(&sa, decls[di]);
                var sa1: []const u8 = "sA"; pal.stderr_write(sa1);
            } else if (decl.kind == AstKind.var_decl and decl.child_0 != 0) {
                var rtype = resolveTypeExpr(ctx, decl.child_0);
                if (rtype != type_mod.TYPE_UNDEFINED) {
                    resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, decl.child_0, rtype);
                    resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, decls[di], rtype);
                }
            }
            if (decl.kind == AstKind.var_decl and decl.child_1 != 0) {
                var init = ctx.store.nodes.items[@intCast(usize, decl.child_1)];
                if (init.kind == AstKind.struct_decl or init.kind == AstKind.union_decl) {
                    var spid = type_mod.nameCacheGet(ctx.typereg, (@intCast(u64, mods[mi].id) << @intCast(u64, 32)) | @intCast(u64, decl.payload));
                    if (spid) |stid| {
                        var sty = ctx.typereg.types_items[@intCast(usize, stid)];
                        var fchildren = ast_mod.astStoreGetExtraChildren(ctx.store, init.payload);
                        var fi2: usize = 0;
                        if (sty.kind == type_mod.TypeKind.struct_type) {
                            var sp = ctx.typereg.st_items[@intCast(usize, sty.payload_idx)];
                            while (fi2 < @intCast(usize, sp.fields_count)) : (fi2 += 1) {
                                var fd = ctx.store.nodes.items[@intCast(usize, fchildren[fi2])];
                                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                                    var ft = resolveTypeExpr(ctx, fd.child_0);
                                    if (ft != type_mod.TYPE_UNDEFINED) {
                                        ctx.typereg.fe_items[@intCast(usize, sp.fields_start) + fi2].type_id = ft;
                                    }
                                }
                            }
                        } else if (sty.kind == type_mod.TypeKind.tagged_union_type) {
                            var tp = ctx.typereg.tu_items[@intCast(usize, sty.payload_idx)];
                            while (fi2 < @intCast(usize, tp.fields_count)) : (fi2 += 1) {
                                var fd = ctx.store.nodes.items[@intCast(usize, fchildren[fi2])];
                                if (fd.kind == AstKind.field_decl and fd.child_0 != 0) {
                                    var ft = resolveTypeExpr(ctx, fd.child_0);
                                    if (ft != type_mod.TYPE_UNDEFINED) {
                                        ctx.typereg.fe_items[@intCast(usize, tp.fields_start) + fi2].type_id = ft;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}

fn resolveStmtTypes(ctx: *CompilerContext, node_idx: u32, depth: u32) void {
    if (depth > @intCast(u32, 16)) return;
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.var_decl) {
        if (node.child_0 != 0) {
            var rtype = resolveTypeExpr(ctx, node.child_0);
            if (rtype != type_mod.TYPE_UNDEFINED) {
                resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, node.child_0, rtype);
                resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, node_idx, rtype);
                var pb = node.child_0 & @intCast(u32, 3);
                if (pb == @intCast(u32, 0)) { var pm: []const u8 = "P0"; pal.stderr_write(pm); }
                else if (pb == @intCast(u32, 1)) { var pm: []const u8 = "P1"; pal.stderr_write(pm); }
                else if (pb == @intCast(u32, 2)) { var pm: []const u8 = "P2"; pal.stderr_write(pm); }
                else { var pm: []const u8 = "P3"; pal.stderr_write(pm); }
            }
        }
    }
    if (node.kind == AstKind.array_init or node.kind == AstKind.struct_init or node.kind == AstKind.tuple_literal) {
        var r0m: []const u8 = "R0n"; pal.stderr_write(r0m);
        var r0b: [20]u8 = undefined;
        var r0l = itoa_mod.itoa(node_idx, r0b[0..]);
        var r0s: usize = @intCast(usize, 19) - @intCast(usize, r0l);
        pal.stderr_write(r0b[r0s..@intCast(usize, 19)]);
        var r0nl: []const u8 = "\n"; pal.stderr_write(r0nl);
        var aii: []const u8 = "AI"; pal.stderr_write(aii);
        if (node.child_0 != 0) {
            var rtype = resolveTypeExpr(ctx, node.child_0);
            var r1m: []const u8 = "R1t"; pal.stderr_write(r1m);
            var r1b: [20]u8 = undefined;
            var r1l = itoa_mod.itoa(rtype, r1b[0..]);
            var r1s: usize = @intCast(usize, 19) - @intCast(usize, r1l);
            pal.stderr_write(r1b[r1s..@intCast(usize, 19)]);
            if (rtype != type_mod.TYPE_UNDEFINED) {
                var r2m: []const u8 = "R2s"; pal.stderr_write(r2m);
                resolved_type_table.resolvedTypeTableSet(ctx.resolved_types, node.child_0, rtype);
            }
            else { var fi: []const u8 = "FI"; pal.stderr_write(fi); }
        }
    }
    if (node.kind == AstKind.block) {
        var decls = ast_mod.astStoreGetExtraChildren(ctx.store, node.payload);
        var di: usize = 0;
        while (di < decls.len) : (di += 1) {
            resolveStmtTypes(ctx, decls[di], depth + @intCast(u32, 1));
        }
    }
    var cd = depth + @intCast(u32, 1);
    if (node.child_0 != 0) { resolveStmtTypes(ctx, node.child_0, cd); }
    if (node.child_1 != 0) { resolveStmtTypes(ctx, node.child_1, cd); }
}

fn resolveTypeExpr(ctx: *CompilerContext, node_idx: u32) type_mod.TypeId {
    return resolveTypeExprDepth(ctx, node_idx, @intCast(u32, 0));
}

fn resolveTypeExprDepth(ctx: *CompilerContext, node_idx: u32, depth: u32) type_mod.TypeId {
    if (depth > @intCast(u32, 16)) return type_mod.TYPE_UNDEFINED;
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.ident_expr) {
        var name_id = ctx.store.identifiers.items[@intCast(usize, node.payload)];
        var tid = type_mod.nameCacheGet(ctx.typereg, @intCast(u64, name_id));
        if (tid) |t| return t;
        var nf: []const u8 = "NF"; pal.stderr_write(nf);
        var mi: usize = 0;
        while (mi < @intCast(usize, ctx.symbol_reg.tables_len)) : (mi += 1) {
            var ck: u64 = @intCast(u64, mi) * @intCast(u64, 4294967296) + @intCast(u64, name_id);
            var tc = type_mod.nameCacheGet(ctx.typereg, ck);
            if (tc) |t| return t;
        }
        var n2: []const u8 = "N2"; pal.stderr_write(n2);
        return type_mod.TYPE_UNDEFINED;
    }
    if (node.child_0 != 0) {
        var child_type = resolveTypeExprDepth(ctx, node.child_0, depth + @intCast(u32, 1));
        if (child_type == type_mod.TYPE_UNDEFINED) return type_mod.TYPE_UNDEFINED;
        if (node.kind == AstKind.ptr_type or node.kind == AstKind.many_ptr_type) {
            return child_type;
        }
        if (node.kind == AstKind.slice_type) {
            var is_const: bool = (node.flags & @intCast(u8, 1)) != @intCast(u8, 0);
            var sl_tid = type_mod.typeRegistryGetOrCreateSlice(ctx.typereg, child_type, is_const);
            var sl_e: [20]u8 = undefined;
            var sl_el = itoa_mod.itoa(child_type, sl_e[0..]);
            var sl_es: usize = @intCast(usize, 19) - @intCast(usize, sl_el);
            var sm: []const u8 = "SL:e"; pal.stderr_write(sm); pal.stderr_write(sl_e[sl_es..@intCast(usize, 19)]);
            var sl_r: [20]u8 = undefined;
            var sl_rl = itoa_mod.itoa(sl_tid, sl_r[0..]);
            var sl_rs: usize = @intCast(usize, 19) - @intCast(usize, sl_rl);
            var s2: []const u8 = "s"; pal.stderr_write(s2); pal.stderr_write(sl_r[sl_rs..@intCast(usize, 19)]);
            var s3: []const u8 = "\n"; pal.stderr_write(s3);
            return sl_tid;
        }
        if (node.kind == AstKind.optional_type) {
            return child_type;
        }
        if (node.kind == AstKind.error_union_type) {
            return child_type;
        }
        if (node.kind == AstKind.array_type) {
            var t0m: []const u8 = "T0"; pal.stderr_write(t0m);
            var t1m: []const u8 = "T1e"; pal.stderr_write(t1m);
            var t1b: [20]u8 = undefined;
            var t1l = itoa_mod.itoa(child_type, t1b[0..]);
            var t1s: usize = @intCast(usize, 19) - @intCast(usize, t1l);
            pal.stderr_write(t1b[t1s..@intCast(usize, 19)]);
            if (node.child_1 != 0) {
                var sz_node = ctx.store.nodes.items[@intCast(usize, node.child_1)];
                var arr_len: u32 = @intCast(u32, 0);
                if (sz_node.kind == AstKind.int_literal) {
                    arr_len = @intCast(u32, ctx.store.int_values.items[@intCast(usize, sz_node.payload)]);
                } else if (sz_node.kind == AstKind.add or sz_node.kind == AstKind.sub) {
                    var lhs = evalConstU32(ctx, sz_node.child_0);
                    var rhs = evalConstU32(ctx, sz_node.child_1);
                    if (lhs != @intCast(u32, 0xFFFFFFFF) and rhs != @intCast(u32, 0xFFFFFFFF)) {
                        if (sz_node.kind == AstKind.add) arr_len = lhs + rhs;
                        else arr_len = lhs - rhs;
                    }
                } else if (sz_node.kind == AstKind.ident_expr) {
                    var c_name_id = ctx.store.identifiers.items[@intCast(usize, sz_node.payload)];
                    var c_sym = sym_mod.symbolRegistryQualifiedLookup(ctx.symbol_reg, @intCast(u32, 0), c_name_id);
                    if (c_sym) |cs| {
                         if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                            var c_decl = ctx.store.nodes.items[@intCast(usize, cs.decl_node)];
                            if (c_decl.child_1 != 0) {
                                var c_init = ctx.store.nodes.items[@intCast(usize, c_decl.child_1)];
                                if (c_init.kind == AstKind.int_literal) {
                                    arr_len = @intCast(u32, ctx.store.int_values.items[@intCast(usize, c_init.payload)]);
                                }
                            }
                        }
                    }
                }
                var t2m: []const u8 = "T2L"; pal.stderr_write(t2m);
                var t2b: [20]u8 = undefined;
                var t2l = itoa_mod.itoa(arr_len, t2b[0..]);
                var t2s: usize = @intCast(usize, 19) - @intCast(usize, t2l);
                pal.stderr_write(t2b[t2s..@intCast(usize, 19)]);
                if (arr_len != @intCast(u32, 0)) {
                    var at = type_mod.typeRegistryGetOrCreateArray(ctx.typereg, child_type, arr_len);
                    var t3m: []const u8 = "T3a"; pal.stderr_write(t3m);
                    var t3b: [20]u8 = undefined;
                    var t3l = itoa_mod.itoa(at, t3b[0..]);
                    var t3s: usize = @intCast(usize, 19) - @intCast(usize, t3l);
                    pal.stderr_write(t3b[t3s..@intCast(usize, 19)]);
                    if (at != type_mod.TYPE_UNDEFINED) { var am: []const u8 = "A"; pal.stderr_write(am); }
                    else { var am: []const u8 = "a"; pal.stderr_write(am); }
                    return at;
                }
            }
            return type_mod.TYPE_UNDEFINED;
        }
    }
    return type_mod.TYPE_UNDEFINED;
}

fn evalConstU32(ctx: *CompilerContext, node_idx: u32) u32 {
    if (node_idx == @intCast(u32, 0)) return @intCast(u32, 0xFFFFFFFF);
    var node = ctx.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.int_literal) {
        return @intCast(u32, ctx.store.int_values.items[@intCast(usize, node.payload)]);
    }
    if (node.kind == AstKind.ident_expr) {
        var name_id = ctx.store.identifiers.items[@intCast(usize, node.payload)];
        var c_sym = sym_mod.symbolRegistryQualifiedLookup(ctx.symbol_reg, @intCast(u32, 0), name_id);
        if (c_sym) |cs| {
            if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                var c_decl = ctx.store.nodes.items[@intCast(usize, cs.decl_node)];
                if (c_decl.child_1 != 0) {
                    return evalConstU32(ctx, c_decl.child_1);
                }
            }
        }
    }
    return @intCast(u32, 0xFFFFFFFF);
}

fn phase_StaticAnalyzers(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "A\n"; pal.stderr_write(p_msg);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    alloc_mod.sandResetPeak(&ctx.alloc.scratch);
    if (ctx.cli.no_null_check != true or ctx.cli.no_lifetime_check != true or ctx.cli.no_leak_check != true) {
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
        while (mi < mods.len) : (mi += 1) {
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
            };
            az_mod.runAllAnalyzers(&ac, ast_root);
        }
    }
}

fn phase_LIRLowering(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "L\n"; pal.stderr_write(p_msg);
    var lnmsg: []const u8 = "nodes="; pal.stderr_write(lnmsg);
    var ln_buf: [20]u8 = undefined;
    var ln_len = itoa_mod.itoa(@intCast(u32, ctx.store.nodes.len), ln_buf[0..]);
    var ln_start: usize = @intCast(usize, 19) - @intCast(usize, ln_len);
    pal.stderr_write(ln_buf[ln_start..@intCast(usize, 19)]);
    var lemsg: []const u8 = " extra="; pal.stderr_write(lemsg);
    var le_buf: [20]u8 = undefined;
    var le_len = itoa_mod.itoa(@intCast(u32, ctx.store.extra_children.len), le_buf[0..]);
    var le_start: usize = @intCast(usize, 19) - @intCast(usize, le_len);
    pal.stderr_write(le_buf[le_start..@intCast(usize, 19)]);
    var lnl: []const u8 = "\n"; pal.stderr_write(lnl);
    alloc_mod.sandReset(&ctx.alloc.scratch);
    ctx.lir_fns.len = @intCast(usize, 0);
    var sem_ctx = SemanticContext{
        .store = ctx.store,
        .registry = ctx.typereg,
        .symbol_tables = ctx.symbol_reg,
        .resolved_types = ctx.resolved_types,
        .coercions = ctx.coercion_table,
        .diag = ctx.diag,
        .has_symbols = @intCast(u8, 1),
        .enum_value_table = &ctx.enum_value_table,
    };
    var mods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    var mi: usize = 0;
    while (mi < mods.len) : (mi += 1) {
        var mm: []const u8 = "M"; pal.stderr_write(mm);
        var mi_buf: [20]u8 = undefined;
        var mi_len = itoa_mod.itoa(@intCast(u32, mi), mi_buf[0..]);
        var mi2_start: usize = @intCast(usize, 19) - @intCast(usize, mi_len);
        pal.stderr_write(mi_buf[mi2_start..@intCast(usize, 19)]);
        var msep: []const u8 = ":"; pal.stderr_write(msep);
        if (mods[mi].ast_root != @intCast(u32, 0)) {
            var ar_buf: [20]u8 = undefined;
            var ar_len = itoa_mod.itoa(mods[mi].ast_root, ar_buf[0..]);
            var ar_start: usize = @intCast(usize, 19) - @intCast(usize, ar_len);
            pal.stderr_write(ar_buf[ar_start..@intCast(usize, 19)]);
            pal.stderr_write(msep);
            var root = ctx.store.nodes.items[@intCast(usize, mods[mi].ast_root)];
            if (root.kind == AstKind.module_root) {
                var mr: []const u8 = "R"; pal.stderr_write(mr);
                var decls = ast_mod.astStoreGetExtraChildren(ctx.store, root.payload);
                var decl_len: u32 = @intCast(u32, decls.len);
                var dcount_buf: [20]u8 = undefined;
                var dcount_len = itoa_mod.itoa(decl_len, dcount_buf[0..]);
                var dstart: usize = @intCast(usize, 19) - @intCast(usize, dcount_len);
                pal.stderr_write(dcount_buf[dstart..@intCast(usize, 19)]);
                pal.stderr_write(msep);
                var di: usize = @intCast(usize, 0);
                while (di < decls.len) : (di += @intCast(usize, 1)) {
                    var decl = ctx.store.nodes.items[@intCast(usize, decls[di])];
                    var raw_k: u32 = @intCast(u32, @enumToInt(decl.kind));
                    var rbuf: [20]u8 = undefined;
                    var rlen = itoa_mod.itoa(raw_k, rbuf[0..]);
                    var rstart: usize = @intCast(usize, 19) - @intCast(usize, rlen);
                    pal.stderr_write(rbuf[rstart..@intCast(usize, 19)]);
                    var sp2: []const u8 = " ";
                    pal.stderr_write(sp2);
                    if (decl.kind == AstKind.fn_decl) {
                        var mf: []const u8 = "F"; pal.stderr_write(mf);
                        var lowerer = lower_mod.lowererInit(&sem_ctx, &ctx.alloc.scratch);
                        lowerer.module_id = mods[mi].id;
                        lowerer.module_reg = ctx.module_reg;
                        var lf = lower_mod.lowerFn(&lowerer, decls[di]);
                        lir_mod.lirFunctionArrayListAppend(&ctx.lir_fns, lf);
                    } else {
        }
    }
    var amods = mr_mod.moduleRegistryGetModules(ctx.module_reg);
    if (amods.len > @intCast(usize, 0) and amods[0].ast_root != @intCast(u32, 0)) {
        var ar = ctx.store.nodes.items[@intCast(usize, amods[0].ast_root)];
        if (ar.kind == AstKind.module_root) {
            var adl = ast_mod.astStoreGetExtraChildren(ctx.store, ar.payload);
            var adi: usize = @intCast(usize, 0);
            var al: []const u8 = "A0"; pal.stderr_write(al);
            while (adi < adl.len) : (adi += @intCast(usize, 1)) {
                var ad = ctx.store.nodes.items[@intCast(usize, adl[adi])];
                var ak: u32 = @intCast(u32, @enumToInt(ad.kind));
                var ab: [20]u8 = undefined;
                var alen = itoa_mod.itoa(ak, ab[0..]);
                var ast: usize = @intCast(usize, 19) - @intCast(usize, alen);
                pal.stderr_write(ab[ast..@intCast(usize, 19)]);
                var asp: []const u8 = " "; pal.stderr_write(asp);
            }
            var an: []const u8 = "\n"; pal.stderr_write(an);
        }
    }
}
        }
    }
}

fn phase_C89Emission(ctx: *CompilerContext) void {
    var p_msg: []const u8 = "C\n"; pal.stderr_write(p_msg);
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
    c89_mod.emitIncludes(&cwriter);
    c89_mod.bufferedWriterFlush(&cwriter);

    c89_mod.emitModule(&emitter, module_name, fns);
    c89_mod.bufferedWriterFlush(&emitter.writer);
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
