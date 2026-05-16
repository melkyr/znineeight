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

pub fn main() void {
    var big_buf: [262144]u8 = undefined;
    var sand = alloc_mod.sandInit(big_buf[0..]);

    var interner = interner_mod.stringInternerInit(&sand, 4);
    token_mod.initKeywordTable(&sand);

    var sm = sm_mod.sourceManagerInit(&sand);
    var diag = diag_mod.diagnosticCollectorInit(&sand, &sm, &interner);

    var src1: []const u8 = "const C = struct { z: u32; }; const y: u32 = 1;";
    var s1: []const u8 = "test struct+var...";
    pal.stdout_write(s1);
    var tokens1: [256]Token = undefined;
    var store1 = ast_mod.astStoreInit(&sand);
    var sm1 = sm_mod.sourceManagerInit(&sand);
    var td1 = diag_mod.diagnosticCollectorInit(&sand, &sm1, &interner);
    var tl1 = lexSource(src1, &interner, &td1, &sand, tokens1[0..]);
    var p1 = parser_mod.parserInit(tokens1[0..tl1], src1, &store1, &interner, &td1, &sand);
    var root1 = parser_mod.parserParseModuleRoot(&p1) catch unreachable;
    var tr1 = type_mod.typeRegistryInit(&sand, &interner);
    type_mod.typeRegistryRegisterPrimitives(&tr1);
    var reg1 = mr_mod.moduleRegistryInit(&sand, &interner, &diag);
    var sym_table1 = sym_mod.symbolRegistryInit(&sand);
    var dg1 = sym_reg.depGraphInit(&sand);
    var mid1 = mr_mod.moduleRegistryAddModule(&reg1, 0);
    var entry1: mr_mod.ModuleEntry = reg1.modules.items[mid1];
    entry1.state = mr_mod.ModuleState.resolved;
    entry1.ast_root = root1;
    reg1.modules.items[mid1] = entry1;
    sym_reg.registerModuleSymbols(&reg1, &sym_table1, &tr1, &store1, mid1, &dg1);
    var resolver1 = type_resolver.typeResolverInit(&tr1, &diag, &sand);
    type_resolver.typeResolverBuild(&resolver1, &dg1);
    type_resolver.typeResolverResolve(&resolver1);
    var b_name: []const u8 = "B";
    var b_id = interner_mod.stringInternerIntern(&interner, b_name);
    var key_b: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, b_id);
    var b_tid_opt = type_mod.nameCacheGet(&tr1, key_b);
    var ok = true;
    if (b_tid_opt) |b_tid| {
        var bty = tr1.types_items[@intCast(usize, b_tid)];
        if (bty.state != @intCast(u8, 2)) ok = false;
        if (bty.size < @intCast(u32, 4)) ok = false;
    } else { ok = false; }
    var a_name: []const u8 = "A";
    var a_id = interner_mod.stringInternerIntern(&interner, a_name);
    var key_a: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, a_id);
    var a_tid_opt = type_mod.nameCacheGet(&tr1, key_a);
    if (a_tid_opt) |a_tid| {
        var aty = tr1.types_items[@intCast(usize, a_tid)];
        if (aty.state != @intCast(u8, 2)) ok = false;
    } else { ok = false; }
    if (ok) {
        var okmsg: []const u8 = "PASS\n"; pal.stdout_write(okmsg);
    } else {
        var failmsg: []const u8 = "FAIL\n"; pal.stdout_write(failmsg); pal.exit(1);
    }

    alloc_mod.sandReset(&sand);
    interner = interner_mod.stringInternerInit(&sand, 4);
    token_mod.initKeywordTable(&sand);

    var src2: []const u8 = "pub const T = struct { x: u32; };";
    var s2: []const u8 = "testCrossModule...";
    pal.stdout_write(s2);
    var tokens2: [256]Token = undefined;
    var store2 = ast_mod.astStoreInit(&sand);
    var sm2 = sm_mod.sourceManagerInit(&sand);
    var td2 = diag_mod.diagnosticCollectorInit(&sand, &sm2, &interner);
    var tl2 = lexSource(src2, &interner, &td2, &sand, tokens2[0..]);
    var p2 = parser_mod.parserInit(tokens2[0..tl2], src2, &store2, &interner, &td2, &sand);
    var root2 = parser_mod.parserParseModuleRoot(&p2) catch unreachable;
    var tr2 = type_mod.typeRegistryInit(&sand, &interner);
    type_mod.typeRegistryRegisterPrimitives(&tr2);
    var reg2 = mr_mod.moduleRegistryInit(&sand, &interner, &diag);
    var sym_table2 = sym_mod.symbolRegistryInit(&sand);
    var dg2 = sym_reg.depGraphInit(&sand);
    var mid2 = mr_mod.moduleRegistryAddModule(&reg2, 0);
    var entry2: mr_mod.ModuleEntry = reg2.modules.items[mid2];
    entry2.state = mr_mod.ModuleState.resolved;
    entry2.ast_root = root2;
    reg2.modules.items[mid2] = entry2;
    sym_reg.registerModuleSymbols(&reg2, &sym_table2, &tr2, &store2, mid2, &dg2);
    var resolver2 = type_resolver.typeResolverInit(&tr2, &diag, &sand);
    type_resolver.typeResolverBuild(&resolver2, &dg2);
    type_resolver.typeResolverResolve(&resolver2);
    var t_name: []const u8 = "T";
    var t_id = interner_mod.stringInternerIntern(&interner, t_name);
    var key_t: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, t_id);
    var t_tid_opt = type_mod.nameCacheGet(&tr2, key_t);
    var ok2 = false;
    if (t_tid_opt) |t_tid| {
        var tty = tr2.types_items[@intCast(usize, t_tid)];
        if (tty.state == @intCast(u8, 2)) ok2 = true;
    }
    if (ok2) {
        var okmsg: []const u8 = "PASS\n"; pal.stdout_write(okmsg);
    } else {
        var failmsg: []const u8 = "FAIL\n"; pal.stdout_write(failmsg); pal.exit(1);
    }

    alloc_mod.sandReset(&sand);
    interner = interner_mod.stringInternerInit(&sand, 4);
    token_mod.initKeywordTable(&sand);

    var src3: []const u8 = "const A = struct { b: B; }; const B = struct { a: A; };";
    var s3: []const u8 = "testCycleDetection...";
    pal.stdout_write(s3);
    var tokens3: [256]Token = undefined;
    var store3 = ast_mod.astStoreInit(&sand);
    var sm3 = sm_mod.sourceManagerInit(&sand);
    var td3 = diag_mod.diagnosticCollectorInit(&sand, &sm3, &interner);
    var tl3 = lexSource(src3, &interner, &td3, &sand, tokens3[0..]);
    var p3 = parser_mod.parserInit(tokens3[0..tl3], src3, &store3, &interner, &td3, &sand);
    var root3 = parser_mod.parserParseModuleRoot(&p3) catch unreachable;
    var tr3 = type_mod.typeRegistryInit(&sand, &interner);
    type_mod.typeRegistryRegisterPrimitives(&tr3);
    var reg3 = mr_mod.moduleRegistryInit(&sand, &interner, &td3);
    var sym_table3 = sym_mod.symbolRegistryInit(&sand);
    var dg3 = sym_reg.depGraphInit(&sand);
    var mid3 = mr_mod.moduleRegistryAddModule(&reg3, 0);
    var entry3: mr_mod.ModuleEntry = reg3.modules.items[mid3];
    entry3.state = mr_mod.ModuleState.resolved;
    entry3.ast_root = root3;
    reg3.modules.items[mid3] = entry3;
    sym_reg.registerModuleSymbols(&reg3, &sym_table3, &tr3, &store3, mid3, &dg3);
    var resolver3 = type_resolver.typeResolverInit(&tr3, &td3, &sand);
    type_resolver.typeResolverBuild(&resolver3, &dg3);
    type_resolver.typeResolverResolve(&resolver3);
    var a3_name: []const u8 = "A";
    var a3_id = interner_mod.stringInternerIntern(&interner, a3_name);
    var key_a3: u64 = @intCast(u64, 0) * @intCast(u64, 4294967296) + @intCast(u64, a3_id);
    var a3_tid_opt = type_mod.nameCacheGet(&tr3, key_a3);
    var ok3 = false;
    if (a3_tid_opt) |a3_tid| {
        var aty = tr3.types_items[@intCast(usize, a3_tid)];
        if (aty.kind == TypeKind.void_type) ok3 = true;
    }
    if (diag_mod.diagnosticCollectorErrorCount(&td3) == @intCast(u32, 0)) ok3 = false;
    if (ok3) {
        var okmsg: []const u8 = "PASS\n"; pal.stdout_write(okmsg);
    } else {
        var failmsg: []const u8 = "FAIL\n"; pal.stdout_write(failmsg); pal.exit(1);
    }

    var m: []const u8 = "All type integration tests passed.\n";
    pal.stdout_write(m);
}
