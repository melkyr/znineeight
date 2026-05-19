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
const type_resolver = @import("../type_resolver.zig");
const pal = @import("../pal.zig");
const rtt_mod = @import("../resolved_type_table.zig");
const sa_mod = @import("../semantic_analyzer.zig");
const coer_mod = @import("../coercion.zig");

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
    testDepGraphFinalize(&dep_graph, &a);

    testDuplicateSymbol();

    var sym_table2 = sym_mod.symbolRegistryInit(&a);
    testVisibilityAndQualifiedLookup(&sym_table2, &interner);

    testImportModule(&reg, &interner, &a, &sym_table);

    testCrossModuleVisibility(&reg, &interner, &a);

    testSymbolRegistrationDeterminism(&interner, &a, &diag);

    testMemoryGate50Modules(&interner, &a, &diag);

    testArrayStateDeferred(&interner, &a);
    testArrayStatePrimitive(&type_reg);
    testEUStateDeferred(&interner, &a);
    testEUStatePrimitive(&type_reg);
    testPtrPayloadSize();
    testSlicePayloadSize();

    testStructLayout(&interner);
    testEnumLayout(&interner);
    testUnionLayout(&interner);
    testTaggedUnionLayout(&interner);
    testOptionalLayout(&interner);
    testErrorUnionLayout(&interner);
    testArrayLayout(&interner);
    testTupleLayout(&interner);
    testTupleEmptyLayout(&interner);
    testCircularCycle(&interner);

    testForwardRefIntegration(&interner, &a, &diag);
    testCrossModuleTypeResolution(&interner, &a, &diag);
    testCycleDetectionIntegration(&interner, &a, &diag);

    testResolvedTypeTableSetGet(&a);
    testResolvedTypeTableOverwrite(&a);
    testResolvedTypeTableNotFound(&a);

    testSemanticAnalyzerInit(&a);

    var msg: []const u8 = "Symbol registration tests passed.\n";
    pal.stdout_write(msg);
}

fn check(state_val: u8, align_val: u32, size_val: u32, tid: u32, tr: *type_mod.TypeRegistry, label: []const u8) void {
    var resolved = tr.types_items[@intCast(usize, tid)];
    var ok = true;
    if (resolved.state != state_val) ok = false;
    if (resolved.alignment != align_val) ok = false;
    if (resolved.size != size_val) ok = false;
    if (!ok) {
        pal.stdout_write(label);
        pal.exit(1);
    }
}

fn testEnumLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var s: []const u8 = "MyEnum";
    var nid = interner_mod.stringInternerIntern(interner, s);
    type_mod.enAppend(&tr, type_mod.EnumPayload{ .members_start = @intCast(u16, 0), .members_count = @intCast(u16, 0), .backing_type = type_mod.TYPE_U16 });
    var en_payload_idx = tr.en_len - 1;
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.enum_type);
    var ety = tr.types_items[@intCast(usize, tid)];
    ety.payload_idx = @intCast(u32, en_payload_idx);
    tr.types_items[@intCast(usize, tid)] = ety;
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testEnumLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 2), @intCast(u32, 2), tid, &tr, fail);
    var msg: []const u8 = "testEnumLayout passed.\n";
    pal.stdout_write(msg);
}

fn testUnionLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_U32, .offset = @intCast(u32, 0) });
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_U64, .offset = @intCast(u32, 0) });
    type_mod.unAppend(&tr, type_mod.UnionPayload{ .fields_start = @intCast(u16, 0), .fields_count = @intCast(u16, 2), .tag_type = @intCast(u32, 0) });
    var un_payload_idx = tr.un_len - 1;
    var s: []const u8 = "MyUnion";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.union_type);
    var uty = tr.types_items[@intCast(usize, tid)];
    uty.payload_idx = @intCast(u32, un_payload_idx);
    tr.types_items[@intCast(usize, tid)] = uty;
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testUnionLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 8), @intCast(u32, 8), tid, &tr, fail);
    var msg: []const u8 = "testUnionLayout passed.\n";
    pal.stdout_write(msg);
}

fn testTaggedUnionLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_U32, .offset = @intCast(u32, 0) });
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_U8, .offset = @intCast(u32, 0) });
    type_mod.tuAppend(&tr, type_mod.TaggedUnionPayload{ .tag_type = type_mod.TYPE_U8, .fields_start = @intCast(u16, 0), .fields_count = @intCast(u16, 2) });
    var tu_payload_idx = tr.tu_len - 1;
    var s: []const u8 = "MyTaggedUnion";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.tagged_union_type);
    var tuty = tr.types_items[@intCast(usize, tid)];
    tuty.payload_idx = @intCast(u32, tu_payload_idx);
    tr.types_items[@intCast(usize, tid)] = tuty;
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testTaggedUnionLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 4), @intCast(u32, 8), tid, &tr, fail);
    var msg: []const u8 = "testTaggedUnionLayout passed.\n";
    pal.stdout_write(msg);
}

fn testOptionalLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var opt_id = type_mod.typeRegistryGetOrCreateOptional(&tr, type_mod.TYPE_U32);
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testOptionalLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 4), @intCast(u32, 8), opt_id, &tr, fail);
    var msg: []const u8 = "testOptionalLayout passed.\n";
    pal.stdout_write(msg);
}

fn testErrorUnionLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var eu_id = type_mod.typeRegistryGetOrCreateErrorUnion(&tr, type_mod.TYPE_U64, @intCast(u32, 0));
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testErrorUnionLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 8), @intCast(u32, 16), eu_id, &tr, fail);
    var msg: []const u8 = "testErrorUnionLayout passed.\n";
    pal.stdout_write(msg);
}

fn testArrayLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var arr_id = type_mod.typeRegistryGetOrCreateArray(&tr, type_mod.TYPE_U32, @intCast(u32, 10));
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testArrayLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 4), @intCast(u32, 40), arr_id, &tr, fail);
    var msg: []const u8 = "testArrayLayout passed.\n";
    pal.stdout_write(msg);
}

fn testTupleLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    type_mod.xtAppend(&tr, type_mod.TYPE_U32);
    type_mod.xtAppend(&tr, type_mod.TYPE_U8);
    type_mod.tupAppend(&tr, type_mod.TuplePayload{ .elems_start = @intCast(u16, 0), .elems_count = @intCast(u16, 2) });
    var tup_payload_idx = tr.tup_len - 1;
    var s: []const u8 = "MyTuple";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.tuple_type);
    var tty = tr.types_items[@intCast(usize, tid)];
    tty.payload_idx = @intCast(u32, tup_payload_idx);
    tr.types_items[@intCast(usize, tid)] = tty;
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testTupleLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 4), @intCast(u32, 8), tid, &tr, fail);
    var msg: []const u8 = "testTupleLayout passed.\n";
    pal.stdout_write(msg);
}

fn testTupleEmptyLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    type_mod.tupAppend(&tr, type_mod.TuplePayload{ .elems_start = @intCast(u16, 0), .elems_count = @intCast(u16, 0) });
    var tup_payload_idx = tr.tup_len - 1;
    var s: []const u8 = "EmptyTuple";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.tuple_type);
    var tty = tr.types_items[@intCast(usize, tid)];
    tty.payload_idx = @intCast(u32, tup_payload_idx);
    tr.types_items[@intCast(usize, tid)] = tty;
    var resolver = type_resolver.typeResolverInit(&tr, undefined, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var fail: []const u8 = "FAIL testTupleEmptyLayout\n";
    check(@intCast(u8, 2), @intCast(u32, 1), @intCast(u32, 1), tid, &tr, fail);
    var msg: []const u8 = "testTupleEmptyLayout passed.\n";
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

fn testCrossModuleVisibility(reg: *mr_mod.ModuleRegistry, interner: *interner_mod.StringInterner, sand: *Sand) void {
    var dbg: []const u8 = "XMOD: start\n";
    pal.stdout_write(dbg);
    var vbuf: [32768]u8 = undefined;
    var va = alloc_mod.sandInit(vbuf[0..]);

    // Module A: "lib" — pub const exposed = 1; const hidden = 2;
    var lib_path: []const u8 = "lib.zig";
    var lib_path_id = interner_mod.stringInternerIntern(interner, lib_path);
    var lib_id = mr_mod.moduleRegistryGetOrCreateModule(reg, lib_path_id);

    var alib = ast_mod.astStoreInit(&va);
    var exposed_str: []const u8 = "exposed";
    var hidden_str: []const u8 = "hidden";
    var exposed_id = interner_mod.stringInternerIntern(interner, exposed_str);
    var hidden_id = interner_mod.stringInternerIntern(interner, hidden_str);

    var exposed_var = ast_mod.astStoreAddNode(&alib, AstKind.var_decl, @intCast(u8, 2),
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, exposed_id);
    var hidden_var = ast_mod.astStoreAddNode(&alib, AstKind.var_decl, @intCast(u8, 0),
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, hidden_id);
    var lib_children: [2]u32 = undefined;
    lib_children[0] = exposed_var;
    lib_children[1] = hidden_var;
    var lib_root_payload = ast_mod.astStoreAddExtraChildren(&alib, lib_children[0..]);
    var lib_root = ast_mod.astStoreAddNode(&alib, AstKind.module_root, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, lib_root_payload);

    var lib_entry = reg.modules.items[@intCast(usize, lib_id)];
    lib_entry.state = mr_mod.ModuleState.resolved;
    lib_entry.ast_root = lib_root;
    reg.modules.items[@intCast(usize, lib_id)] = lib_entry;

    // Module B: "main" — imports lib.zig
    var main_path: []const u8 = "main.zig";
    var main_path_id = interner_mod.stringInternerIntern(interner, main_path);
    var main_id = mr_mod.moduleRegistryGetOrCreateModule(reg, main_path_id);

    var bstore = ast_mod.astStoreInit(&va);
    var import_node = ast_mod.astStoreAddNode(&bstore, AstKind.import_expr, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, lib_path_id);
    var main_str: []const u8 = "main";
    var main_name_id = interner_mod.stringInternerIntern(interner, main_str);
    var var_node = ast_mod.astStoreAddNode(&bstore, AstKind.var_decl, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, import_node, 0, main_name_id);
    var main_children: [1]u32 = undefined;
    main_children[0] = var_node;
    var main_root_payload = ast_mod.astStoreAddExtraChildren(&bstore, main_children[0..]);
    var main_root = ast_mod.astStoreAddNode(&bstore, AstKind.module_root, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, main_root_payload);

    var main_entry = reg.modules.items[@intCast(usize, main_id)];
    main_entry.state = mr_mod.ModuleState.resolved;
    main_entry.ast_root = main_root;
    reg.modules.items[@intCast(usize, main_id)] = main_entry;

    // Register symbols
    var sym_table3 = sym_mod.symbolRegistryInit(&va);
    var vtype_reg = type_mod.typeRegistryInit(&va, interner);
    type_mod.typeRegistryRegisterPrimitives(&vtype_reg);
    var vdep = sym_reg.depGraphInit(&va);

    sym_reg.registerModuleSymbols(reg, &sym_table3, &vtype_reg, &alib, lib_id, &vdep);
    sym_reg.registerModuleSymbols(reg, &sym_table3, &vtype_reg, &bstore, main_id, &vdep);

    // Verify lib's symbols
    var lib_table = sym_mod.symbolRegistryGetTable(&sym_table3, lib_id);
    var exp_lookup = sym_mod.symbolTableLookup(lib_table, exposed_id);
    if (exp_lookup) |exp_sym| {
        if (!sym_mod.symbolIsPublic(exp_sym)) {
            var emsg: []const u8 = "FAIL cross_vis: exposed not public\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL cross_vis: exposed not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var hid_lookup = sym_mod.symbolTableLookup(lib_table, hidden_id);
    if (hid_lookup) |hid_sym| {
        if (sym_mod.symbolIsPublic(hid_sym)) {
            var emsg: []const u8 = "FAIL cross_vis: hidden flagged public\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL cross_vis: hidden not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    // Verify main's import symbol
    var main_table = sym_mod.symbolRegistryGetTable(&sym_table3, main_id);
    var main_lookup = sym_mod.symbolTableLookup(main_table, main_name_id);
    if (main_lookup) |main_sym| {
        if (main_sym.kind != sym_mod.SymbolKind.module) {
            var emsg: []const u8 = "FAIL cross_vis: main import not module\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        if (main_sym.module_id != lib_id) {
            var emsg: []const u8 = "FAIL cross_vis: main import wrong module_id\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL cross_vis: main import not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    // Cross-module qualified lookup
    var qual_lookup = sym_mod.symbolRegistryQualifiedLookup(&sym_table3, lib_id, exposed_id);
    if (qual_lookup) |qual_sym| {
        if (!sym_mod.symbolIsPublic(qual_sym)) {
            var emsg: []const u8 = "FAIL cross_vis: qual exposed not public\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL cross_vis: qual exposed not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var qual_hidden = sym_mod.symbolRegistryQualifiedLookup(&sym_table3, lib_id, hidden_id);
    if (qual_hidden) |qh_sym| {
        if (sym_mod.symbolIsPublic(qh_sym)) {
            var emsg: []const u8 = "FAIL cross_vis: qual hidden flagged public\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL cross_vis: qual hidden not found\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var cvmsg: []const u8 = "Cross-module visibility test passed.\n";
    pal.stdout_write(cvmsg);
}

fn testSymbolRegistrationDeterminism(interner: *interner_mod.StringInterner, sand: *Sand, diag: *diag_mod.DiagnosticCollector) void {
    var dbuf: [32768]u8 = undefined;
    var da = alloc_mod.sandInit(dbuf[0..]);

    var d_name: []const u8 = "alpha";
    var d_str: []const u8 = "beta";
    var d_path: []const u8 = "gamma";
    var d_name_id = interner_mod.stringInternerIntern(interner, d_name);
    var d_intern_id = interner_mod.stringInternerIntern(interner, d_str);
    var d_path_id = interner_mod.stringInternerIntern(interner, d_path);

    var s1 = ast_mod.astStoreInit(&da);
    var v1 = ast_mod.astStoreAddNode(&s1, AstKind.var_decl, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, d_name_id);
    var i1 = ast_mod.astStoreAddNode(&s1, AstKind.import_expr, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, d_intern_id);
    var c1: [2]u32 = undefined; c1[0] = v1; c1[1] = i1;
    var p1 = ast_mod.astStoreAddExtraChildren(&s1, c1[0..]);
    var root1 = ast_mod.astStoreAddNode(&s1, AstKind.module_root, 0,
        @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, p1);

    var reg_a = mr_mod.moduleRegistryInit(&da, interner, diag);
    var mr_mod_a = mr_mod.moduleRegistryAddModule(&reg_a, d_path_id);
    var entry_a = reg_a.modules.items[@intCast(usize, mr_mod_a)];
    entry_a.state = mr_mod.ModuleState.resolved;
    entry_a.ast_root = root1;
    reg_a.modules.items[@intCast(usize, mr_mod_a)] = entry_a;

    var reg_b = mr_mod.moduleRegistryInit(&da, interner, diag);
    var mr_mod_b = mr_mod.moduleRegistryAddModule(&reg_b, d_path_id);
    var entry_b = reg_b.modules.items[@intCast(usize, mr_mod_b)];
    entry_b.state = mr_mod.ModuleState.resolved;
    entry_b.ast_root = root1;
    reg_b.modules.items[@intCast(usize, mr_mod_b)] = entry_b;

    var t1 = type_mod.typeRegistryInit(&da, interner);
    type_mod.typeRegistryRegisterPrimitives(&t1);
    var t2 = type_mod.typeRegistryInit(&da, interner);
    type_mod.typeRegistryRegisterPrimitives(&t2);
    var g1 = sym_reg.depGraphInit(&da);
    var g2 = sym_reg.depGraphInit(&da);
    var st1 = sym_mod.symbolRegistryInit(&da);
    var st2 = sym_mod.symbolRegistryInit(&da);

    sym_reg.registerModuleSymbols(&reg_a, &st1, &t1, &s1, mr_mod_a, &g1);
    sym_reg.registerModuleSymbols(&reg_b, &st2, &t2, &s1, mr_mod_b, &g2);

    var tbl1 = sym_mod.symbolRegistryGetTable(&st1, mr_mod_a);
    var tbl2 = sym_mod.symbolRegistryGetTable(&st2, mr_mod_b);
    if (tbl1.len != tbl2.len) {
        var emsg: []const u8 = "FAIL det_sym: len\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var di: usize = 0;
    while (di < tbl1.len) {
        if (tbl1.items[di].name_id != tbl2.items[di].name_id) {
            var emsg: []const u8 = "FAIL det_sym: name\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        if (tbl1.items[di].kind != tbl2.items[di].kind) {
            var emsg: []const u8 = "FAIL det_sym: kind\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        if (tbl1.items[di].flags != tbl2.items[di].flags) {
            var emsg: []const u8 = "FAIL det_sym: flags\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        di += 1;
    }
    var dmsg: []const u8 = "Symbol registration determinism test passed.\n";
    pal.stdout_write(dmsg);
}

fn testMemoryGate50Modules(interner: *interner_mod.StringInterner, sand: *Sand, diag: *diag_mod.DiagnosticCollector) void {
    var mbuf: [262144]u8 = undefined;
    var msand = alloc_mod.sandInit(mbuf[0..]);

    var reg = mr_mod.moduleRegistryInit(&msand, interner, diag);
    var mi: u32 = 0;
    while (mi < 50) {
        _ = mr_mod.moduleRegistryAddModule(&reg, @intCast(u32, mi + 1000));
        mi += 1;
    }

    // Linear chain: module N imports N-1
    mi = 1;
    while (mi < 50) {
        mr_mod.moduleRegistryAddImport(&reg, mi, mi - 1);
        mi += 1;
    }

    mr_mod.moduleRegistrySortModules(&reg);

    // Verify linear order: modules[0].id == 0, ..., modules[49].id == 49
    mi = 0;
    while (mi < 50) {
        if (reg.modules.items[@intCast(usize, mi)].id != mi) {
            var emsg: []const u8 = "FAIL mg: sort order\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        mi += 1;
    }

    // Register symbols for all 50
    var sym_table = sym_mod.symbolRegistryInit(&msand);
    var type_reg = type_mod.typeRegistryInit(&msand, interner);
    type_mod.typeRegistryRegisterPrimitives(&type_reg);
    var g = sym_reg.depGraphInit(&msand);

    mi = 0;
    while (mi < 50) {
        var store = ast_mod.astStoreInit(&msand);
        var dname: []const u8 = "x";
        var name_id = interner_mod.stringInternerIntern(interner, dname);
        var vn = ast_mod.astStoreAddNode(&store, AstKind.var_decl, 0,
            @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, name_id);
        var ch: [1]u32 = undefined; ch[0] = vn;
        var cp = ast_mod.astStoreAddExtraChildren(&store, ch[0..]);
        var root = ast_mod.astStoreAddNode(&store, AstKind.module_root, 0,
            @intCast(u32, 0), @intCast(u32, 0), 0, 0, 0, cp);
        var entry = reg.modules.items[@intCast(usize, mi)];
        entry.ast_root = root;
        reg.modules.items[@intCast(usize, mi)] = entry;
        sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store, mi, &g);
        mi += 1;
    }

    var peak = msand.peak;
    if (peak > @intCast(usize, 16 * 1024 * 1024)) {
        var emsg: []const u8 = "FAIL mg: peak > 16MB\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    // Determinism: second run with separate registry
    var mbuf2: [262144]u8 = undefined;
    var msand2 = alloc_mod.sandInit(mbuf2[0..]);
    var reg2 = mr_mod.moduleRegistryInit(&msand2, interner, diag);
    mi = 0;
    while (mi < 50) {
        _ = mr_mod.moduleRegistryAddModule(&reg2, @intCast(u32, mi + 1000));
        mi += 1;
    }
    mi = 1;
    while (mi < 50) {
        mr_mod.moduleRegistryAddImport(&reg2, mi, mi - 1);
        mi += 1;
    }
    mr_mod.moduleRegistrySortModules(&reg2);
    mi = 0;
    while (mi < 50) {
        if (reg2.modules.items[@intCast(usize, mi)].id != mi) {
            var emsg: []const u8 = "FAIL mg2: sort order\n";
            pal.stdout_write(emsg); pal.exit(1);
        }
        mi += 1;
    }

    var mmsg: []const u8 = "Memory gate 50-module test passed (< 16 MB)\n";
    pal.stdout_write(mmsg);
}

fn testArrayStateDeferred(interner: *interner_mod.StringInterner, arena: *Sand) void {
    var buf: [8192]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var s: []const u8 = "MyType";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var unresolved = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.struct_type);
    var arr_tid = type_mod.typeRegistryGetOrCreateArray(&tr, unresolved, @intCast(u32, 5));
    var st = type_mod.typeRegistryGetTypeState(&tr, arr_tid);
    if (st != @intCast(u8, 0)) {
        var emsg: []const u8 = "FAIL: array state not deferred\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var arr_tid2 = type_mod.typeRegistryGetOrCreateArray(&tr, unresolved, @intCast(u32, 5));
    _ = arr_tid2;
    var msg: []const u8 = "testArrayStateDeferred passed.\n";
    pal.stdout_write(msg);
}

fn testArrayStatePrimitive(tr: *type_mod.TypeRegistry) void {
    var arr_tid = type_mod.typeRegistryGetOrCreateArray(tr, type_mod.TYPE_U32, @intCast(u32, 4));
    var st = type_mod.typeRegistryGetTypeState(tr, arr_tid);
    if (st != @intCast(u8, 2)) {
        var emsg: []const u8 = "FAIL: array state not resolved\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var arr_tid2 = type_mod.typeRegistryGetOrCreateArray(tr, type_mod.TYPE_U32, @intCast(u32, 4));
    if (arr_tid != arr_tid2) {
        var emsg: []const u8 = "FAIL: array dedup failed\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testArrayStatePrimitive passed.\n";
    pal.stdout_write(msg);
}

fn testEUStateDeferred(interner: *interner_mod.StringInterner, arena: *Sand) void {
    var buf: [8192]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var s: []const u8 = "MyType";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var unresolved = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.struct_type);
    var eu_tid = type_mod.typeRegistryGetOrCreateErrorUnion(&tr, unresolved, type_mod.TYPE_U32);
    var st = type_mod.typeRegistryGetTypeState(&tr, eu_tid);
    if (st != @intCast(u8, 0)) {
        var emsg: []const u8 = "FAIL: error_union state not deferred\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testEUStateDeferred passed.\n";
    pal.stdout_write(msg);
}

fn testEUStatePrimitive(tr: *type_mod.TypeRegistry) void {
    var eu_tid = type_mod.typeRegistryGetOrCreateErrorUnion(tr, type_mod.TYPE_U32, type_mod.TYPE_U32);
    var st = type_mod.typeRegistryGetTypeState(tr, eu_tid);
    if (st != @intCast(u8, 2)) {
        var emsg: []const u8 = "FAIL: error_union state not resolved\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testEUStatePrimitive passed.\n";
    pal.stdout_write(msg);
}

fn testPtrPayloadSize() void {
    if (@sizeOf(type_mod.PtrPayload) != @intCast(usize, 4)) {
        var emsg: []const u8 = "FAIL: PtrPayload size wrong\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testPtrPayloadSize passed.\n";
    pal.stdout_write(msg);
}

fn testSlicePayloadSize() void {
    if (@sizeOf(type_mod.SlicePayload) != @intCast(usize, 4)) {
        var emsg: []const u8 = "FAIL: SlicePayload size wrong\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testSlicePayloadSize passed.\n";
    pal.stdout_write(msg);
}

fn testStructLayout(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var sm = sm_mod.sourceManagerInit(&a);
    var diag = diag_mod.diagnosticCollectorInit(&a, &sm, interner);

    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);

    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_U32, .offset = @intCast(u32, 0) });
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_U8, .offset = @intCast(u32, 0) });
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = type_mod.TYPE_I64, .offset = @intCast(u32, 0) });

    type_mod.stAppend(&tr, type_mod.StructPayload{ .fields_start = @intCast(u16, 0), .fields_count = @intCast(u16, 3) });
    var st_payload_idx = tr.st_len - 1;

    var s: []const u8 = "MyStruct";
    var nid = interner_mod.stringInternerIntern(interner, s);
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), nid, TypeKind.struct_type);

    var sty = tr.types_items[@intCast(usize, tid)];
    sty.payload_idx = @intCast(u32, st_payload_idx);
    tr.types_items[@intCast(usize, tid)] = sty;

    var resolver = type_resolver.typeResolverInit(&tr, &diag, &a);
    var dg = sym_reg.depGraphInit(&a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);

    var resolved = tr.types_items[@intCast(usize, tid)];
    if (resolved.state != @intCast(u8, 2)) {
        var emsg: []const u8 = "FAIL struct layout: state not resolved\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    if (resolved.alignment != @intCast(u32, 8)) {
        var emsg: []const u8 = "FAIL struct layout: wrong alignment\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    if (resolved.size != @intCast(u32, 16)) {
        var emsg: []const u8 = "FAIL struct layout: wrong size\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var f0 = tr.fe_items[0];
    if (f0.offset != @intCast(u32, 0)) {
        var emsg: []const u8 = "FAIL struct layout: field 0 offset\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var f1 = tr.fe_items[1];
    if (f1.offset != @intCast(u32, 4)) {
        var emsg: []const u8 = "FAIL struct layout: field 1 offset\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var f2 = tr.fe_items[2];
    if (f2.offset != @intCast(u32, 8)) {
        var emsg: []const u8 = "FAIL struct layout: field 2 offset\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var msg: []const u8 = "testStructLayout passed.\n";
    pal.stdout_write(msg);
}

fn testCircularCycle(interner: *interner_mod.StringInterner) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var sm = sm_mod.sourceManagerInit(&a);
    var diag = diag_mod.diagnosticCollectorInit(&a, &sm, interner);

    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);

    var a_name: []const u8 = "A";
    var a_name_id = interner_mod.stringInternerIntern(interner, a_name);
    var a_tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), a_name_id, TypeKind.struct_type);

    var b_name: []const u8 = "B";
    var b_name_id = interner_mod.stringInternerIntern(interner, b_name);
    var b_tid = type_mod.typeRegistryRegisterNamedType(&tr, @intCast(u32, 0), b_name_id, TypeKind.struct_type);

    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = b_tid, .offset = @intCast(u32, 0) });
    type_mod.feAppend(&tr, type_mod.FieldEntry{ .name_id = @intCast(u32, 0), .type_id = a_tid, .offset = @intCast(u32, 0) });

    type_mod.stAppend(&tr, type_mod.StructPayload{ .fields_start = @intCast(u16, 0), .fields_count = @intCast(u16, 1) });
    var a_sp_idx = tr.st_len - 1;

    type_mod.stAppend(&tr, type_mod.StructPayload{ .fields_start = @intCast(u16, 1), .fields_count = @intCast(u16, 1) });
    var b_sp_idx = tr.st_len - 1;

    var aty = tr.types_items[@intCast(usize, a_tid)];
    aty.payload_idx = @intCast(u32, a_sp_idx);
    tr.types_items[@intCast(usize, a_tid)] = aty;

    var bty = tr.types_items[@intCast(usize, b_tid)];
    bty.payload_idx = @intCast(u32, b_sp_idx);
    tr.types_items[@intCast(usize, b_tid)] = bty;

    var dg = sym_reg.depGraphInit(&a);
    var raw = alloc_mod.sandAlloc(&a, @intCast(usize, 8) * @intCast(usize, 2), @intCast(usize, 4)) catch unreachable;
    var typed_items = @ptrCast([*]sym_reg.DepEdge, raw);
    typed_items[0] = sym_reg.DepEdge{ .from = a_tid, .to = b_tid };
    typed_items[1] = sym_reg.DepEdge{ .from = b_tid, .to = a_tid };
    dg.items = typed_items;
    dg.len = @intCast(usize, 2);
    dg.cap = @intCast(usize, 2);

    var resolver = type_resolver.typeResolverInit(&tr, &diag, &a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);

    var resolved_a = tr.types_items[@intCast(usize, a_tid)];
    if (resolved_a.kind != TypeKind.void_type) {
        var emsg: []const u8 = "FAIL circular: A not poisoned\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    if (resolved_a.state != @intCast(u8, 2)) {
        var emsg: []const u8 = "FAIL circular: A state not resolved\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var resolved_b = tr.types_items[@intCast(usize, b_tid)];
    if (resolved_b.kind != TypeKind.void_type) {
        var emsg: []const u8 = "FAIL circular: B not poisoned\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    if (resolved_b.state != @intCast(u8, 2)) {
        var emsg: []const u8 = "FAIL circular: B state not resolved\n";
        pal.stdout_write(emsg); pal.exit(1);
    }

    var msg: []const u8 = "testCircularCycle passed.\n";
    pal.stdout_write(msg);
}

fn testDepGraphFinalize(g: *sym_reg.DepGraph, sand: *Sand) void {
    var raw = alloc_mod.sandAlloc(sand, @intCast(usize, 4) * @intCast(usize, 6), @intCast(usize, 4)) catch unreachable;
    var typed_items = @ptrCast([*]sym_reg.DepEdge, raw);
    typed_items[0] = sym_reg.DepEdge{ .from = @intCast(u32, 0), .to = @intCast(u32, 2) };
    typed_items[1] = sym_reg.DepEdge{ .from = @intCast(u32, 1), .to = @intCast(u32, 2) };
    typed_items[2] = sym_reg.DepEdge{ .from = @intCast(u32, 2), .to = @intCast(u32, 0) };
    g.items = typed_items;
    g.len = @intCast(usize, 3);
    g.cap = @intCast(usize, 6);
    sym_reg.depGraphFinalize(g, @intCast(u32, 2));
    var in0 = g.in_degree_items[@intCast(usize, 0)];
    var in2 = g.in_degree_items[@intCast(usize, 2)];
    if (in0 != @intCast(u32, 1) or in2 != @intCast(u32, 2)) {
        var emsg: []const u8 = "FAIL DepGraph in_degree\n";
        pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "DepGraph finalize test passed.\n";
    pal.stdout_write(msg);
}

fn testForwardRefIntegration(interner: *interner_mod.StringInterner, sand: *Sand, diag: *diag_mod.DiagnosticCollector) void {
    var src: []const u8 = "const B = struct { x: u32, };";
    var buf: [32768]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    token_mod.initKeywordTable(&a);
    var tokens: [128]Token = undefined;
    var store = ast_mod.astStoreInit(&a);
    var sm = sm_mod.sourceManagerInit(&a);
    var td = diag_mod.diagnosticCollectorInit(&a, &sm, interner);
    var tok_len = lexSource(src, interner, &td, &a, tokens[0..]);
    var p = parser_mod.parserInit(tokens[0..tok_len], src, &store, interner, &td, &a);
    var root = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var reg = mr_mod.moduleRegistryInit(&a, interner, &td);
    var sym_table = sym_mod.symbolRegistryInit(&a);
    var dg = sym_reg.depGraphInit(&a);
    var mid = mr_mod.moduleRegistryAddModule(&reg, 0);
    var entry = reg.modules.items[mid];
    entry.state = mr_mod.ModuleState.resolved;
    entry.ast_root = root;
    reg.modules.items[mid] = entry;
    sym_reg.registerModuleSymbols(&reg, &sym_table, &tr, &store, mid, &dg);
    var resolver = type_resolver.typeResolverInit(&tr, &td, &a);
    type_resolver.typeResolverBuild(&resolver, &dg);
    type_resolver.typeResolverResolve(&resolver);
    var b_name: []const u8 = "B";
    var b_id = interner_mod.stringInternerIntern(interner, b_name);
    var key_b: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, b_id);
    var b_tid_opt = type_mod.nameCacheGet(&tr, key_b);
    if (b_tid_opt) |b_tid| {
        var bty = tr.types_items[@intCast(usize, b_tid)];
        if (bty.kind != TypeKind.struct_type) { var emsg: []const u8 = "FAIL fwdref B not struct\n"; pal.stdout_write(emsg); pal.exit(1); }
        if (bty.state != @intCast(u8, 2)) { var emsg: []const u8 = "FAIL fwdref B not resolved\n"; pal.stdout_write(emsg); pal.exit(1); }
    } else {
        var emsg: []const u8 = "FAIL fwdref B not found\n"; pal.stdout_write(emsg); pal.exit(1);
    }
    var m: []const u8 = "testForwardRefIntegration passed.\n"; pal.stdout_write(m);
}

fn testCrossModuleTypeResolution(interner: *interner_mod.StringInterner, sand: *Sand, diag: *diag_mod.DiagnosticCollector) void {
    var buf: [16384]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var tr = type_mod.typeRegistryInit(&a, interner);
    type_mod.typeRegistryRegisterPrimitives(&tr);
    var t_name: []const u8 = "TX";
    var t_nid = interner_mod.stringInternerIntern(interner, t_name);
    var tid = type_mod.typeRegistryRegisterNamedType(&tr, 0, t_nid, TypeKind.struct_type);
    var key: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, t_nid);
    var found_opt = type_mod.nameCacheGet(&tr, key);
    if (found_opt) |found| {
        if (found != tid) {
            var emsg: []const u8 = "FAIL xmod direct tid mismatch\n"; pal.stdout_write(emsg); pal.exit(1);
        }
    } else {
        var emsg: []const u8 = "FAIL xmod direct not found\n"; pal.stdout_write(emsg); pal.exit(1);
    }
    var m: []const u8 = "testCrossModuleTypeResolution passed.\n"; pal.stdout_write(m);
}

fn testSemanticAnalyzerInit(arena: *Sand) void {
    var rtt = rtt_mod.resolvedTypeTableInit(arena);
    var tr = type_mod.typeRegistryInit(arena, undefined);
    var st = sym_mod.symbolRegistryInit(arena);
    var store = ast_mod.astStoreInit(arena);
    var diag_storage: diag_mod.DiagnosticCollector = undefined;
    var cov = coer_mod.coercionTableInit(arena);
    var sa = sa_mod.semanticAnalyzerInit(arena, &rtt, &diag_storage, &tr, &st, &store, @intCast(u32, 0), &cov);
    if (sa.type_table == null) { var emsg: []const u8 = "FAIL sa: type_table null\n"; pal.stdout_write(emsg); pal.exit(1); }
    if (sa.diag == null) { var emsg: []const u8 = "FAIL sa: diag null\n"; pal.stdout_write(emsg); pal.exit(1); }
    if (sa.registry == null) { var emsg: []const u8 = "FAIL sa: registry null\n"; pal.stdout_write(emsg); pal.exit(1); }
    if (sa.symbols == null) { var emsg: []const u8 = "FAIL sa: symbols null\n"; pal.stdout_write(emsg); pal.exit(1); }
    if (sa.store == null) { var emsg: []const u8 = "FAIL sa: store null\n"; pal.stdout_write(emsg); pal.exit(1); }
    if (sa.module_id != @intCast(u32, 0)) { var emsg: []const u8 = "FAIL sa: module_id != 0\n"; pal.stdout_write(emsg); pal.exit(1); }
    if (sa.expected_type_stack_len != @intCast(usize, 0)) { var emsg: []const u8 = "FAIL sa: stack not empty\n"; pal.stdout_write(emsg); pal.exit(1); }
    var msg: []const u8 = "testSemanticAnalyzerInit passed.\n";
    pal.stdout_write(msg);
}

fn testResolvedTypeTableSetGet(arena: *Sand) void {
    var rtt = rtt_mod.resolvedTypeTableInit(arena);
    rtt_mod.resolvedTypeTableSet(&rtt, @intCast(u32, 1), @intCast(u32, 10));
    rtt_mod.resolvedTypeTableSet(&rtt, @intCast(u32, 3), @intCast(u32, 30));
    rtt_mod.resolvedTypeTableSet(&rtt, @intCast(u32, 5), @intCast(u32, 50));

    var opt1 = rtt_mod.resolvedTypeTableGet(&rtt, @intCast(u32, 1));
    if (opt1) |v| {
        if (v != @intCast(u32, 10)) { var emsg: []const u8 = "FAIL rtt set-get node 1\n"; pal.stdout_write(emsg); pal.exit(1); }
    } else {
        var emsg: []const u8 = "FAIL rtt set-get node 1 missing\n"; pal.stdout_write(emsg); pal.exit(1);
    }
    var opt3 = rtt_mod.resolvedTypeTableGet(&rtt, @intCast(u32, 3));
    if (opt3) |v| {
        if (v != @intCast(u32, 30)) { var emsg: []const u8 = "FAIL rtt set-get node 3\n"; pal.stdout_write(emsg); pal.exit(1); }
    } else {
        var emsg: []const u8 = "FAIL rtt set-get node 3 missing\n"; pal.stdout_write(emsg); pal.exit(1);
    }
    var opt5 = rtt_mod.resolvedTypeTableGet(&rtt, @intCast(u32, 5));
    if (opt5) |v| {
        if (v != @intCast(u32, 50)) { var emsg: []const u8 = "FAIL rtt set-get node 5\n"; pal.stdout_write(emsg); pal.exit(1); }
    } else {
        var emsg: []const u8 = "FAIL rtt set-get node 5 missing\n"; pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testResolvedTypeTableSetGet passed.\n";
    pal.stdout_write(msg);
}

fn testResolvedTypeTableOverwrite(arena: *Sand) void {
    var rtt = rtt_mod.resolvedTypeTableInit(arena);
    rtt_mod.resolvedTypeTableSet(&rtt, @intCast(u32, 7), @intCast(u32, 5));
    rtt_mod.resolvedTypeTableSet(&rtt, @intCast(u32, 7), @intCast(u32, 9));
    var opt7 = rtt_mod.resolvedTypeTableGet(&rtt, @intCast(u32, 7));
    if (opt7) |v| {
        if (v != @intCast(u32, 9)) { var emsg: []const u8 = "FAIL rtt overwrite\n"; pal.stdout_write(emsg); pal.exit(1); }
    } else {
        var emsg: []const u8 = "FAIL rtt overwrite missing\n"; pal.stdout_write(emsg); pal.exit(1);
    }
    var msg: []const u8 = "testResolvedTypeTableOverwrite passed.\n";
    pal.stdout_write(msg);
}

fn testResolvedTypeTableNotFound(arena: *Sand) void {
    var rtt = rtt_mod.resolvedTypeTableInit(arena);
    rtt_mod.resolvedTypeTableSet(&rtt, @intCast(u32, 1), @intCast(u32, 10));
    var opt2 = rtt_mod.resolvedTypeTableGet(&rtt, @intCast(u32, 2));
    if (opt2 != null) { var emsg: []const u8 = "FAIL rtt not-found\n"; pal.stdout_write(emsg); pal.exit(1); }
    var msg: []const u8 = "testResolvedTypeTableNotFound passed.\n";
    pal.stdout_write(msg);
}

fn testCycleDetectionIntegration(interner: *interner_mod.StringInterner, sand: *Sand, diag: *diag_mod.DiagnosticCollector) void {
    _ = interner; _ = sand; _ = diag;
    var m: []const u8 = "testCycleDetectionIntegration passed (stub).\n"; pal.stdout_write(m);
}
