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

    var mod_id = mr_mod.moduleRegistryAddModule(&reg, 0);
    var entry = reg.modules.items[mod_id];
    entry.state = mr_mod.ModuleState.resolved;
    entry.ast_root = root;
    reg.modules.items[mod_id] = entry;

    sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store, mod_id);
    testVarDecl(&sym_table, &interner, mod_id);

    entry.ast_root = root2;
    reg.modules.items[mod_id] = entry;
    sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store2, mod_id);
    testFnDecl(&sym_table, &interner, mod_id);

    entry.ast_root = root3;
    reg.modules.items[mod_id] = entry;
    sym_reg.registerModuleSymbols(&reg, &sym_table, &type_reg, &store3, mod_id);
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

    var msg: []const u8 = "Symbol registration tests passed.\n";
    pal.stdout_write(msg);
}
