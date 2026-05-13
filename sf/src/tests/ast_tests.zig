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
    testVisitPreOrder();
    testVisitOrder();
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
    assertEqU32(@intCast(u32, @sizeOf(FnProto)), @intCast(u32, 12));
}

fn testAstStoreInit() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    assertEqU32(@intCast(u32, store.nodes.len), @intCast(u32, 1));
    assertEqU32(@intCast(u32, @enumToInt(store.nodes.items[0].kind)), @intCast(u32, 0));
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
    assertEqU32(store.nodes.items[idx].span_start, @intCast(u32, 5));
    assertEqU32(@intCast(u32, store.nodes.items[idx].span_len), @intCast(u32, 5));
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
    var retrieved = ast_mod.astStoreGetExtraChildren(&store, payload);
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
    var retrieved = ast_mod.astStoreGetExtraChildren(&store, payload);
    assertEqU32(retrieved.len, @intCast(usize, 0));
}

fn testAstStoreAddIntLiteral() void {
    var buf: [65536]u8 = undefined;
    var sand = alloc_mod.sandInit(buf[0..65536]);
    var store = ast_mod.astStoreInit(&sand);
    var idx = ast_mod.astStoreAddIntLiteral(&store, @intCast(u64, 255), @intCast(u32, 0), @intCast(u32, 3));
    assertEqU32(idx, @intCast(u32, 1));
    assertEqU64(store.int_values.items[0], @intCast(u64, 255));
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
    assertEqU32(store.identifiers.items[0], @intCast(u32, 7));
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
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.switch_expr));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.tuple_literal));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.struct_init));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.array_init));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.module_root));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.switch_prong));
    assertTrue(ast_mod.nodeHasExtraChildren(AstKind.error_set_decl));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.int_literal));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.ident_expr));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.var_decl));
    assertTrue(!ast_mod.nodeHasExtraChildren(AstKind.if_stmt));
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
