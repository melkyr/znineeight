const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const token_mod = @import("../token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const lexer_mod = @import("../lexer.zig");
const parser_mod = @import("../parser.zig");
const ast_mod = @import("../ast.zig");
const AstKind = ast_mod.AstKind;
const mr_mod = @import("../module_registry.zig");
const sym_mod = @import("../symbol_table.zig");
const sym_reg = @import("../symbol_registrator.zig");
const type_mod = @import("../type_registry.zig");
const TypeKind = type_mod.TypeKind;
const pal = @import("../pal.zig");

fn lexSource(content: []const u8, interner: *interner_mod.StringInterner, diag: *diag_mod.DiagnosticCollector, sand: *Sand, tokens: []Token) usize {
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), interner, diag, sand);
    var i: usize = 0;
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tokens[i] = t;
        i += 1;
        if (t.kind == TokenKind.eof) break;
    }
    return i;
}

fn testVarDecl(sym_table: *sym_mod.SymbolRegistry, interner: *interner_mod.StringInterner, mod_id: u32) void {
    var x_name: []const u8 = "x";
    var x_id = interner_mod.stringInternerIntern(interner, x_name);
    var table = sym_mod.symbolRegistryGetTable(sym_table, mod_id);
    var found = sym_mod.symbolTableLookup(table, x_id);
    if (found) |sym| {
        if (sym.kind != sym_mod.SymbolKind.global) {
            var msg: []const u8 = "FAIL var kind\n";
            pal.stdout_write(msg);
            pal.exit(1);
        }
    } else {
        var msg: []const u8 = "FAIL: 'x' not found (var name_id bug)\n";
        pal.stdout_write(msg);
        pal.exit(1);
    }
}

fn testFnDecl(sym_table: *sym_mod.SymbolRegistry, interner: *interner_mod.StringInterner, mod_id: u32) void {
    var f_name: []const u8 = "foo";
    var f_id = interner_mod.stringInternerIntern(interner, f_name);
    var table = sym_mod.symbolRegistryGetTable(sym_table, mod_id);
    var found = sym_mod.symbolTableLookup(table, f_id);
    if (found) |sym| {
        if (sym.kind != sym_mod.SymbolKind.function) {
            var msg: []const u8 = "FAIL fn kind\n";
            pal.stdout_write(msg);
            pal.exit(1);
        }
    } else {
        var msg: []const u8 = "FAIL: 'foo' not found (fn name_id bug)\n";
        pal.stdout_write(msg);
        pal.exit(1);
    }
}

fn testNamedTestDecl(sym_table: *sym_mod.SymbolRegistry, mod_id: u32) void {
    var table = sym_mod.symbolRegistryGetTable(sym_table, mod_id);
    // Find a symbol with test_sym kind — any named test
    var i: usize = 0;
    var found_test = false;
    while (i < table.len) {
        if (table.items[i].kind == sym_mod.SymbolKind.test_sym) { found_test = true; }
        i += 1;
    }
    if (!found_test) {
        var msg: []const u8 = "FAIL: no test symbol found\n";
        pal.stdout_write(msg);
        pal.exit(1);
    }
}

fn testUnnamedTestDecl(sym_table: *sym_mod.SymbolRegistry, mod_id: u32) void {
    var table = sym_mod.symbolRegistryGetTable(sym_table, mod_id);
    if (table.len != @intCast(usize, 3)) {
        var msg: []const u8 = "FAIL: unnamed test created symbol\n";
        pal.stdout_write(msg);
        pal.exit(1);
    }
}

pub fn main() void {
    var buf: [131072]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var interner = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var diag = diag_mod.diagnosticCollectorInit(&a, &sm, &interner);
    token_mod.initKeywordTable(&a);

    var var_content: []const u8 = "const x: u32 = 42;";
    var var_tokens: [32]Token = undefined;
    var var_tok_len = lexSource(var_content, &interner, &diag, &a, var_tokens[0..]);
    var store = ast_mod.astStoreInit(&a);
    var p = parser_mod.parserInit(var_tokens[0..var_tok_len], var_content, &store, &interner, &diag, &a);
    var root = parser_mod.parserParseModuleRoot(&p) catch unreachable;

    var fn_content: []const u8 = "const x: u32 = 42; fn foo() void {}";
    var fn_tokens: [64]Token = undefined;
    var fn_tok_len = lexSource(fn_content, &interner, &diag, &a, fn_tokens[0..]);
    var store2 = ast_mod.astStoreInit(&a);
    var p2 = parser_mod.parserInit(fn_tokens[0..fn_tok_len], fn_content, &store2, &interner, &diag, &a);
    var root2 = parser_mod.parserParseModuleRoot(&p2) catch unreachable;

    var test_content: []const u8 = "const x: u32 = 42; fn foo() void {} test \"my test\" {} test {}";
    var test_tokens: [128]Token = undefined;
    var test_tok_len = lexSource(test_content, &interner, &diag, &a, test_tokens[0..]);
    var store3 = ast_mod.astStoreInit(&a);
    var p3 = parser_mod.parserInit(test_tokens[0..test_tok_len], test_content, &store3, &interner, &diag, &a);
    var root3 = parser_mod.parserParseModuleRoot(&p3) catch unreachable;

    var reg = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var sym_table = sym_mod.symbolRegistryInit(&a);
    var type_reg = type_mod.typeRegistryInit(&a, &interner);
    type_mod.typeRegistryRegisterPrimitives(&type_reg);

    var dep_graph = sym_reg.depGraphInit(&a);

    var mod_id = mr_mod.moduleRegistryAddModule(&reg, 0);
    var entry = reg.modules.items[mod_id];
    entry.state = mr_mod.ModuleState.resolved;
    entry.ast_root = root;
    reg.modules.items[mod_id] = entry;

    sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store, mod_id, &dep_graph);
    testVarDecl(&sym_table, &interner, mod_id);

    entry.ast_root = root2;
    reg.modules.items[mod_id] = entry;
    sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store2, mod_id, &dep_graph);
    testFnDecl(&sym_table, &interner, mod_id);

    entry.ast_root = root3;
    reg.modules.items[mod_id] = entry;
    sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store3, mod_id, &dep_graph);
    testNamedTestDecl(&sym_table, mod_id);
    testUnnamedTestDecl(&sym_table, mod_id);

    var s1: []const u8 = "MyStruct";
    var s2: []const u8 = "MyEnum";
    var n1_id = interner_mod.stringInternerIntern(&interner, s1);
    var n2_id = interner_mod.stringInternerIntern(&interner, s2);
    var t1 = type_mod.typeRegistryRegisterNamedType(&type_reg, 0, n1_id, TypeKind.struct_type);
    var t2 = type_mod.typeRegistryRegisterNamedType(&type_reg, 0, n2_id, TypeKind.enum_type);
    _ = t2;
    var key1: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, n1_id);
    var found1 = type_mod.nameCacheGet(&type_reg, key1);
    if (found1) |val| {
        if (val != t1) {
            var msg: []const u8 = "FAIL name_cache wrong tid\n";
            pal.stdout_write(msg); pal.exit(1);
        }
    } else {
        var msg: []const u8 = "FAIL name_cache miss\n";
        pal.stdout_write(msg); pal.exit(1);
    }
    var key_wrong: u64 = @intCast(u64, 1) * @intCast(u64, 4294967296) + @intCast(u64, n1_id);
    var found2 = type_mod.nameCacheGet(&type_reg, key_wrong);
    if (found2 != null) {
        var msg: []const u8 = "FAIL name_cache wrong module match\n";
        pal.stdout_write(msg); pal.exit(1);
    }

    testRegisterNamedTypeAndDepGraph(&type_reg, &interner, &dep_graph, &a);

    testDuplicateSymbol();

    var sym_table2 = sym_mod.symbolRegistryInit(&a);
    testVisibilityAndQualifiedLookup(&sym_table2, &interner);

    testImportModule(&reg, &interner, &a, &sym_table);

    var msg: []const u8 = "Symbol registration tests passed.\n";
    pal.stdout_write(msg);
}

fn testVisibilityAndQualifiedLookup(sym_table: *sym_mod.SymbolRegistry, interner: *interner_mod.StringInterner) void {
    var vbuf: [16384]u8 = undefined;
    var va = alloc_mod.sandInit(vbuf[0..]);
    var v_interner = interner_mod.stringInternerInit(&va, @intCast(u32, 4));
    var vsm = sm_mod.sourceManagerInit(&va);
    var vdiag = diag_mod.diagnosticCollectorInit(&va, &vsm, &v_interner);
    token_mod.initKeywordTable(&va);

    var content: []const u8 = "pub const x: u32 = 42; fn hidden() void {}";
    var vtokens: [64]Token = undefined;
    var tok_len = lexSource(content, &v_interner, &vdiag, &va, vtokens[0..]);
    var vstore = ast_mod.astStoreInit(&va);
    var vp = parser_mod.parserInit(vtokens[0..tok_len], content, &vstore, &v_interner, &vdiag, &va);
    var root = parser_mod.parserParseModuleRoot(&vp) catch unreachable;

    var vreg = mr_mod.moduleRegistryInit(&va, &v_interner, &vdiag);
    var vtype_reg = type_mod.typeRegistryInit(&va, &v_interner);
    type_mod.typeRegistryRegisterPrimitives(&vtype_reg);
    var vdep = sym_reg.depGraphInit(&va);
    var vmod_id = mr_mod.moduleRegistryAddModule(&vreg, @intCast(u32, 0));
    var ventry = vreg.modules.items[@intCast(usize, vmod_id)];
    ventry.state = mr_mod.ModuleState.resolved;
    ventry.ast_root = root;
    vreg.modules.items[@intCast(usize, vmod_id)] = ventry;
    sym_reg.registerModuleSymbols(&vreg, sym_table, &vtype_reg, &vstore, vmod_id, &vdep);

    var x_name: []const u8 = "x";
    var x_id = interner_mod.stringInternerIntern(&v_interner, x_name);
    var h_name: []const u8 = "hidden";
    var h_id = interner_mod.stringInternerIntern(&v_interner, h_name);

    var x_found = sym_mod.symbolRegistryQualifiedLookup(sym_table, vmod_id, x_id);
    if (x_found) |xsym| {
        if (!sym_mod.symbolIsPublic(xsym)) {
            var emsg: []const u8 = "FAIL: pub x not public\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL: x not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var h_found = sym_mod.symbolRegistryQualifiedLookup(sym_table, vmod_id, h_id);
    if (h_found) |hsym| {
        if (sym_mod.symbolIsPublic(hsym)) {
            var emsg: []const u8 = "FAIL: hidden flagged as public\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL: hidden not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var h_found2 = sym_mod.symbolRegistryQualifiedLookup(sym_table, vmod_id, h_id);
    if (h_found2 == null) {
        var emsg: []const u8 = "FAIL: qualifiedLookup miss on private\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var vmsg: []const u8 = "Visibility flags test passed.\n";
    pal.stdout_write(vmsg);
    var qmsg: []const u8 = "Qualified lookup test passed.\n";
    pal.stdout_write(qmsg);
}

fn testRegisterNamedTypeAndDepGraph(type_reg: *type_mod.TypeRegistry, interner: *interner_mod.StringInterner, dep_graph: *sym_reg.DepGraph, sand: *Sand) void {
    var t_name: []const u8 = "MyStruct";
    var t_name_id = interner_mod.stringInternerIntern(interner, t_name);
    var t_tid = type_mod.typeRegistryRegisterNamedType(type_reg, @intCast(u32, 0), t_name_id, TypeKind.struct_type);
    var tkey: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, t_name_id);
    var t_found = type_mod.nameCacheGet(type_reg, tkey);
    if (t_found) |t_val| {
        if (t_val != t_tid) {
            var emsg: []const u8 = "FAIL type stub: wrong tid\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL type stub: name_cache miss\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var t_type = type_reg.types_items[@intCast(usize, t_tid)];
    if (t_type.kind != TypeKind.struct_type or t_type.state != @intCast(u8, 0)) {
        var emsg: []const u8 = "FAIL type stub: wrong kind or state\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var tmsg: []const u8 = "Type stub creation test passed.\n";
    pal.stdout_write(tmsg);

    sym_reg.depGraphAddEdge(dep_graph, @intCast(u32, 0), t_tid);
    sym_reg.depGraphAddEdge(dep_graph, t_tid, @intCast(u32, 0));
    if (dep_graph.len != @intCast(usize, 2)) {
        var emsg: []const u8 = "FAIL DepGraph edges\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var dmsg: []const u8 = "DepGraph edges test passed.\n";
    pal.stdout_write(dmsg);
}

fn testDuplicateSymbol() void {
    var dbuf: [4096]u8 = undefined;
    var da = alloc_mod.sandInit(dbuf[0..]);
    var dsym_table = sym_mod.symbolRegistryInit(&da);
    var dtable = sym_mod.symbolRegistryGetTable(&dsym_table, @intCast(u32, 0));
    var dsym = sym_mod.Symbol{
        .name_id = @intCast(u32, 42),
        .type_id = @intCast(u32, 0),
        .kind = sym_mod.SymbolKind.global,
        .flags = @intCast(u16, 0),
        .decl_node = @intCast(u32, 0),
        .module_id = @intCast(u32, 0),
        .scope_level = @intCast(u32, 0),
    };
    var first = sym_mod.symbolTableInsert(dtable, dsym);
    _ = first;
    var second = sym_mod.symbolTableInsert(dtable, dsym);
    if (second) {
        var dmsg: []const u8 = "FAIL duplicate: insert returned true\n";
        pal.stdout_write(dmsg); pal.exit(1);
    }
    if (dtable.len != @intCast(usize, 1)) {
        var dmsg: []const u8 = "FAIL duplicate: table grew on dup\n";
        pal.stdout_write(dmsg); pal.exit(1);
    }
    var dmsg: []const u8 = "Duplicate symbol test passed.\n";
    pal.stdout_write(dmsg);
}

fn testImportModule(reg: *mr_mod.ModuleRegistry, interner: *interner_mod.StringInterner, sand: *Sand, sym_table: *sym_mod.SymbolRegistry) void {
    var ibuf: [16384]u8 = undefined;
    var ia = alloc_mod.sandInit(ibuf[0..]);

    var ipath_src: []const u8 = "lib/sand.zig";
    var ipath_id = interner_mod.stringInternerIntern(interner, ipath_src);
    var imod_id = mr_mod.moduleRegistryGetOrCreateModule(reg, ipath_id);

    var istore = ast_mod.astStoreInit(&ia);
    var import_node = ast_mod.astStoreAddNode(&istore, AstKind.import_expr, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, ipath_id);
    var iname: []const u8 = "sand_mod";
    var iname_id = interner_mod.stringInternerIntern(interner, iname);
    var ivar_node = ast_mod.astStoreAddNode(&istore, AstKind.var_decl, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, import_node, 0, iname_id);
    var ichildren: [1]u32 = undefined;
    ichildren[0] = ivar_node;
    var iroot_payload = ast_mod.astStoreAddExtraChildren(&istore, ichildren[0..]);
    var iroot = ast_mod.astStoreAddNode(&istore, AstKind.module_root, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, iroot_payload);

    var itype_reg = type_mod.typeRegistryInit(&ia, interner);
    type_mod.typeRegistryRegisterPrimitives(&itype_reg);
    var idep = sym_reg.depGraphInit(&ia);

    var ireg_mod_id = mr_mod.moduleRegistryAddModule(reg, @intCast(u32, 0));
    var ientry = reg.modules.items[@intCast(usize, ireg_mod_id)];
    ientry.state = mr_mod.ModuleState.resolved;
    ientry.ast_root = iroot;
    reg.modules.items[@intCast(usize, ireg_mod_id)] = ientry;

    sym_reg.registerModuleSymbols(reg, sym_table, &itype_reg, &istore, ireg_mod_id, &idep);

    var isym_table = sym_mod.symbolRegistryGetTable(sym_table, ireg_mod_id);
    var ifound = sym_mod.symbolTableLookup(isym_table, iname_id);
    if (ifound) |isym| {
        if (isym.kind != sym_mod.SymbolKind.module) {
            var emsg: []const u8 = "FAIL import: kind not module\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        if (isym.module_id != imod_id) {
            var emsg: []const u8 = "FAIL import: wrong module_id\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL import: symbol not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var imsg: []const u8 = "Import module test passed.\n";
    pal.stdout_write(imsg);
}
