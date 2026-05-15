const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const rtt_mod = @import("resolved_type_table.zig");
const type_mod = @import("type_registry.zig");
const diag_mod = @import("diagnostics.zig");

pub const SemanticAnalyzer = struct {
    type_table: *ResolvedTypeTable,
    diag: *DiagnosticCollector,
    registry: *TypeRegistry,
    symbols: *SymbolRegistry,
    store: *AstStore,
    module_id: u32,
    expected_type_stack_items: [*]TypeId,
    expected_type_stack_len: usize,
    expected_type_stack_cap: usize,
    expected_type_stack_alloc: *Sand,
    current_fn_return: TypeId,
    current_fn_name: u32,
};

pub fn semanticAnalyzerInit(alloc: *Sand, type_table: *ResolvedTypeTable, diag: *DiagnosticCollector, registry: *TypeRegistry, symbols: *SymbolRegistry, store: *AstStore, module_id: u32) SemanticAnalyzer {
    return SemanticAnalyzer{
        .type_table = type_table,
        .diag = diag,
        .registry = registry,
        .symbols = symbols,
        .store = store,
        .module_id = module_id,
        .expected_type_stack_items = undefined,
        .expected_type_stack_len = @intCast(usize, 0),
        .expected_type_stack_cap = @intCast(usize, 0),
        .expected_type_stack_alloc = alloc,
        .current_fn_return = @intCast(u32, 0),
        .current_fn_name = @intCast(u32, 0),
    };
}

pub fn semanticAnalyzerResolveExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var result: u32;
    result = @intCast(u32, 0);
    if (node_idx == @intCast(u32, 0)) return result;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    result = type_mod.TYPE_VOID;

    if (node.kind == AstKind.int_literal) {
        result = type_mod.TYPE_INT_LIT;
    } else if (node.kind == AstKind.float_literal) {
        result = type_mod.TYPE_F64;
    } else if (node.kind == AstKind.char_literal) {
        result = type_mod.TYPE_U8;
    } else if (node.kind == AstKind.bool_literal) {
        result = type_mod.TYPE_BOOL;
    } else if (node.kind == AstKind.null_literal) {
        result = type_mod.TYPE_NULL;
    } else if (node.kind == AstKind.undefined_literal) {
        result = type_mod.TYPE_UNDEFINED;
    } else if (node.kind == AstKind.unreachable_expr) {
        result = type_mod.TYPE_NORETURN;
    } else if (node.kind == AstKind.string_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.enum_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.error_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.ident_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.field_access) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.index_access) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.slice_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.deref) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.address_of) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.fn_call) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.builtin_call) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.bool_not) {
        result = type_mod.TYPE_BOOL;
    } else if (node.kind == AstKind.negate) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.bit_not) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.try_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.catch_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.orelse_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.if_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.switch_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.tuple_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.struct_init) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.array_init) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.ptr_type or node.kind == AstKind.many_ptr_type or
               node.kind == AstKind.array_type or node.kind == AstKind.slice_type or
               node.kind == AstKind.optional_type or node.kind == AstKind.error_union_type or
               node.kind == AstKind.fn_type or node.kind == AstKind.struct_decl or
               node.kind == AstKind.enum_decl or node.kind == AstKind.union_decl or
               node.kind == AstKind.error_set_decl) {
        result = type_mod.TYPE_TYPE;
    } else if (node.kind == AstKind.paren_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.expr_stmt) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.block) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op or node.kind == AstKind.bit_and or
               node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
               node.kind == AstKind.shl or node.kind == AstKind.shr or
               node.kind == AstKind.bool_and or node.kind == AstKind.bool_or or
               node.kind == AstKind.cmp_eq or node.kind == AstKind.cmp_ne or
               node.kind == AstKind.cmp_lt or node.kind == AstKind.cmp_le or
               node.kind == AstKind.cmp_gt or node.kind == AstKind.cmp_ge or
               node.kind == AstKind.assign or node.kind == AstKind.add_assign or
               node.kind == AstKind.sub_assign or node.kind == AstKind.mul_assign or
               node.kind == AstKind.div_assign or node.kind == AstKind.mod_assign or
               node.kind == AstKind.shl_assign or node.kind == AstKind.shr_assign or
               node.kind == AstKind.and_assign or node.kind == AstKind.or_assign or
               node.kind == AstKind.xor_assign) {
        result = type_mod.TYPE_VOID;
    } else {
        result = type_mod.TYPE_VOID;
    }

    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
    return result;
}
