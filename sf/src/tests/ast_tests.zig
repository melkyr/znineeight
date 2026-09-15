const Sand = @import("../allocator.zig").Sand;
const alloc_mod = @import("../allocator.zig");
const ast_mod = @import("../ast.zig");
const AstKind = ast_mod.AstKind;
const AstNode = ast_mod.AstNode;
const FnProto = ast_mod.FnProto;
const AstStore = ast_mod.AstStore;
fn assertTrue(condition: bool) void {
    if (!condition) @panic("assertTrue failed");
}
fn assertEqU32(actual: u32, expected: u32) void {
    if (actual != expected) @panic("assertEqU32 failed");
}
fn assertEqU64(actual: u64, expected: u64) void {
    if (actual != expected) @panic("assertEqU64 failed");
}

const ChildAuditEntry = struct {
    kind: AstKind,
    m0: bool,
    m1: bool,
    m2: bool,
    extra: bool,
};

pub fn runAstUnitTests() void {
    testAstKindErrSentinel();
    testAstNodeSize();
    testFnProtoSize();
    testAstStoreInit();
    testAstStoreAddNode();
    testAstStoreAddNodeSpan();
    testAstStoreAddExtraChildren();
    testAstStoreGetExtraChildren();
    testAstStoreAddIntLiteral();
    testAstStoreAddFloatLiteral();
    testAstStoreAddStringLiteral();
    testAstStoreAddIdentifier();
    testNodeHasExtraChildren();
    testNodeChildIsNodeAudit();
    testVisitPreOrder();
    testVisitOrder();
    testValidityValid();
    testValidityBadChild();
    testValidityBadPayload();
    testAstKindCollisionFree();
    testAstMemoryBudget();
    //testVisitCombined();
    //testVisitDeep();
    //testVisitLargeExtra();
    //testVisitEmptyBlock();
}

fn testAstKindErrSentinel() void {
    assertEqU32(@intCast(u32, @enumToInt(AstKind.err)), @intCast(u32, 0));
}

fn testAstNodeSize() void {
    assertEqU32(@intCast(u32, @sizeOf(AstNode)), @intCast(u32, 24));
}

fn testFnProtoSize() void {
    assertEqU32(@intCast(u32, @sizeOf(FnProto)), @intCast(u32, 16));
}

fn testAstStoreInit() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    assertEqU32(@intCast(u32, store.nodes.len), @intCast(u32, 1));
    assertEqU32(@intCast(u32, @enumToInt(ast_mod.astStoreNodeAt(&store, 0).kind)), @intCast(u32, 0));
}

fn testAstStoreAddNode() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0),
        @intCast(u32, 10), @intCast(u32, 12),
        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 42));
    assertEqU32(idx, @intCast(u32, 1));
    assertEqU32(@intCast(u32, store.nodes.len), @intCast(u32, 2));
}

fn testAstStoreAddNodeSpan() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0),
        @intCast(u32, 5), @intCast(u32, 10),
        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    assertEqU32(ast_mod.astStoreNodeAt(&store, idx).span_start, @intCast(u32, 5));
    assertEqU32(@intCast(u32, ast_mod.astStoreNodeAt(&store, idx).span_len), @intCast(u32, 5));
}

fn testAstStoreAddExtraChildren() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var children: [3]u32 = undefined;
    children[0] = @intCast(u32, 10);
    children[1] = @intCast(u32, 20);
    children[2] = @intCast(u32, 30);
    var payload = ast_mod.astStoreAddExtraChildren(&store, children[0..3]);
    assertEqU32(store.extra_children.len, @intCast(usize, 3));
    var retrieved = ast_mod.astStoreGetExtraChildren(&store, store.extra_ranges.items[@intCast(usize, payload)]);
    assertEqU32(retrieved.len, @intCast(usize, 3));
    assertEqU32(retrieved[0], @intCast(u32, 10));
    assertEqU32(retrieved[1], @intCast(u32, 20));
    assertEqU32(retrieved[2], @intCast(u32, 30));
}

fn testAstStoreGetExtraChildren() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var empty: []const u32 = undefined;
    var payload = ast_mod.astStoreAddExtraChildren(&store, empty[0..0]);
    var retrieved = ast_mod.astStoreGetExtraChildren(&store, store.extra_ranges.items[@intCast(usize, payload)]);
    assertEqU32(retrieved.len, @intCast(usize, 0));
}

fn testAstStoreAddIntLiteral() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 255), @intCast(u32, 0), @intCast(u32, 3));
    assertEqU32(idx, @intCast(u32, 1));
    assertEqU64(ast_mod.astStoreIntValue(&store, idx), @intCast(u64, 255));
}

fn testAstStoreAddFloatLiteral() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddFloatLiteral(&store, 3.14, @intCast(u32, 0), @intCast(u32, 4));
    assertEqU32(idx, @intCast(u32, 1));
}

fn testAstStoreAddStringLiteral() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddStringLiteral(&store, @intCast(u32, 42), @intCast(u32, 1), @intCast(u32, 6));
    assertEqU32(idx, @intCast(u32, 1));
    assertEqU32(store.string_values.items[0], @intCast(u32, 42));
}

fn testAstStoreAddIdentifier() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, @intCast(u32, 7), @intCast(u32, 2), @intCast(u32, 5));
    assertEqU32(idx, @intCast(u32, 1));
    assertEqU32(ast_mod.astStoreIdentifier(&store, idx), @intCast(u32, 7));
}

var g_visit_count: u32 = 0;

fn visitIncCount(store: *AstStore, node_idx: u32) void {
    _ = store;
    _ = node_idx;
    g_visit_count += 1;
}

fn testNodeHasExtraChildren() void {
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.fn_call));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.block));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.struct_decl));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.enum_decl));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.union_decl));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.swt_ex));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.tuple_literal));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.struct_init));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.array_init));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.module_root));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.swt_prong));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.error_set_decl));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.int_literal));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.ident_expr));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.var_decl));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.if_stmt));
}

fn testNodeChildIsNodeAudit() void {
    const table = [112]ChildAuditEntry{
        ChildAuditEntry{ .kind = AstKind.err, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.var_decl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.fn_decl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.struct_decl, .m0 = false, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.enum_decl, .m0 = false, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.union_decl, .m0 = false, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.field_decl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.param_decl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.test_decl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.error_set_decl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.int_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.float_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.string_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.char_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bool_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.null_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.undefined_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.unreachable_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.enum_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.error_literal, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.tuple_literal, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.struct_init, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.array_init, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.field_init, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.ident_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.field_access, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.index_access, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.slice_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.deref, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.address_of, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.fn_call, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.builtin_call, .m0 = false, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.paren_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.add, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sub, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.mul, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.div, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.mod_op, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bit_and, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bit_or, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bit_xor, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.shl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.shr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bool_and, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bool_or, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.cmp_eq, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.cmp_ne, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.cmp_lt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.cmp_le, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.cmp_gt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.cmp_ge, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.plain_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.add_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sub_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.mul_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.div_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.swt_ex, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.shl_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.shr_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.and_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.xor_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.or_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.negate, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bool_not, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.bit_not, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.try_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.catch_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.orelse_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.if_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.if_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.if_capture, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.while_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.while_capture, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.for_stmt, .m0 = true, .m1 = true, .m2 = false, .extra = false },
        ChildAuditEntry{ .kind = AstKind.mod_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.swt_prong, .m0 = true, .m1 = false, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.block, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.return_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.break_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.continue_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.defer_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.errdefer_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.labeled_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.expr_stmt, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.ptr_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.many_ptr_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.array_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.slice_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.optional_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.error_union_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.fn_type, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.import_expr, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.module_root, .m0 = true, .m1 = true, .m2 = true, .extra = true },
        ChildAuditEntry{ .kind = AstKind.payload_capture, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.range_exclusive, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.range_inclusive, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.c_include, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_add, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_sub, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_mul, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_negate, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_add_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_sub_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.wrap_mul_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_add, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_sub, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_mul, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_shl, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_add_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_sub_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_mul_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
        ChildAuditEntry{ .kind = AstKind.sat_shl_assign, .m0 = true, .m1 = true, .m2 = true, .extra = false },
    };
    assertEqU32(@intCast(u32, table.len), @intCast(u32, 112));
    var i: usize = 0;
    while (i < table.len) : (i += 1) {
        var e = table[i];
        assertTrue(ast_mod.nodeChildIsNode(e.kind, @intCast(u8, 0)) == e.m0);
        assertTrue(ast_mod.nodeChildIsNode(e.kind, @intCast(u8, 1)) == e.m1);
        assertTrue(ast_mod.nodeChildIsNode(e.kind, @intCast(u8, 2)) == e.m2);
        assertTrue(ast_mod.nodeHasNodeExtraChildren(e.kind) == e.extra);
    }
}

fn testVisitPreOrder() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var a_idx = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 42), @intCast(u32, 0), @intCast(u32, 2));
    var b_idx = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 99), @intCast(u32, 3), @intCast(u32, 5));
    var children: [2]u32 = undefined;
    children[0] = a_idx;
    children[1] = b_idx;
    var payload = ast_mod.astStoreAddExtraChildren(&store, children[0..2]);
    var block_idx = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0),
        @intCast(u32, 0), @intCast(u32, 5),
        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), payload);
    g_visit_count = @intCast(u32, 0);
    ast_mod.visitPreOrder(&store, block_idx, visitIncCount);
    assertEqU32(g_visit_count, @intCast(u32, 3));
}

var g_visit_tracker: [16]u32 = undefined;
var g_visit_tracker_idx: u32 = 0;

fn visitTracker(store: *AstStore, node_idx: u32) void {
    _ = store;
    g_visit_tracker[g_visit_tracker_idx] = node_idx;
    g_visit_tracker_idx += 1;
}

fn testVisitOrder() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var child_a = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 10), @intCast(u32, 0), @intCast(u32, 2));
    var child_b = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 20), @intCast(u32, 2), @intCast(u32, 4));
    var child_c = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 30), @intCast(u32, 4), @intCast(u32, 6));
    var parent = ast_mod.astStoreAddNode(&store, AstKind.ident_expr, @intCast(u8, 0),
        @intCast(u32, 0), @intCast(u32, 6),
        child_a, child_b, child_c, @intCast(u32, 0));
    g_visit_tracker_idx = @intCast(u32, 0);
    ast_mod.visitPreOrder(&store, parent, visitTracker);
    assertEqU32(g_visit_tracker_idx, @intCast(u32, 4));
    assertEqU32(g_visit_tracker[0], parent);
    assertEqU32(g_visit_tracker[1], child_a);
    assertEqU32(g_visit_tracker[2], child_b);
    assertEqU32(g_visit_tracker[3], child_c);
}

var g_validate_ok: bool = true;

fn validateNode(store: *AstStore, node_idx: u32) void {
    if (!g_validate_ok) return;
    if (@intCast(usize, node_idx) >= store.nodes.len) { g_validate_ok = false; return; }
    var node = ast_mod.astStoreNodeAt(store, node_idx);
    if (node.child_0 != 0 and @intCast(usize, node.child_0) >= store.nodes.len) { g_validate_ok = false; return; }
    if (node.child_1 != 0 and @intCast(usize, node.child_1) >= store.nodes.len) { g_validate_ok = false; return; }
    if (node.child_2 != 0 and @intCast(usize, node.child_2) >= store.nodes.len) { g_validate_ok = false; return; }
    if (!ast_mod.nodeHasExtraChildren(node.kind) and ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
        if (node.kind == AstKind.int_literal or node.kind == AstKind.char_literal) {
            if (@intCast(usize, ast_mod.astStoreNodePayload(store, node_idx)) >= store.int_values.len) { g_validate_ok = false; return; }
        } else if (node.kind == AstKind.float_literal) {
            if (@intCast(usize, ast_mod.astStoreNodePayload(store, node_idx)) >= store.float_values.len) { g_validate_ok = false; return; }
        }
    }
}

fn astStoreValidate(store: *AstStore, root: u32) bool {
    if (root == 0) return false;
    if (@intCast(usize, root) >= store.nodes.len) return false;
    g_validate_ok = true;
    ast_mod.visitPreOrder(store, root, validateNode);
    return g_validate_ok;
}

fn testValidityValid() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var a = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 10), @intCast(u32, 0), @intCast(u32, 2));
    var b = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 20), @intCast(u32, 2), @intCast(u32, 4));
    var children: [2]u32 = undefined;
    children[0] = a;
    children[1] = b;
    var payload = ast_mod.astStoreAddExtraChildren(&store, children[0..2]);
    var block = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0),
        @intCast(u32, 0), @intCast(u32, 4),
        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), payload);
    assertTrue(astStoreValidate(&store, block));
}

fn testValidityBadChild() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var bad = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0),
        @intCast(u32, 0), @intCast(u32, 2),
        @intCast(u32, 999), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0));
    assertTrue(!astStoreValidate(&store, bad));
}

fn testValidityBadPayload() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var bad = ast_mod.astStoreAddNode(&store, AstKind.int_literal, @intCast(u8, 0),
        @intCast(u32, 0), @intCast(u32, 2),
        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 999));
    assertTrue(!astStoreValidate(&store, bad));
}

fn testAstKindCollisionFree() void {
    assertTrue(@enumToInt(AstKind.mod_assign) != @enumToInt(AstKind.swt_ex));
}

fn testAstMemoryBudget() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var a = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 42), @intCast(u32, 0), @intCast(u32, 2));
    var b = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 99), @intCast(u32, 3), @intCast(u32, 5));
    _ = a; _ = b;
    var mem = ast_mod.astStoreComputeMemory(&store);
    var node_mem = @sizeOf(AstNode);
    assertTrue(mem > @intCast(u64, node_mem));
    assertTrue(mem < @intCast(u64, 65536));
}
