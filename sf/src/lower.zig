pub const DeferAction = struct {
    kind: u8,
    ast_node: u32,
    scope_depth: u32,
};

pub const LirLowerer = struct {
    func: *LirFunction,
    current_bb: u32,
    temp_counter: u32,
    store: *AstStore,
    registry: *TypeRegistry,
    symbol_tables: *SymbolRegistry,
    resolved_types: *ResolvedTypeTable,
    coercions: *CoercionTable,
    defer_stack: std.ArrayList(DeferAction),
    loop_stack: std.ArrayList(u32),
    diag: *DiagnosticCollector,
    allocator: *Allocator,

    pub fn init(store: *AstStore, registry: *TypeRegistry, symbol_tables: *SymbolRegistry, resolved_types: *ResolvedTypeTable, coercions: *CoercionTable, diag: *DiagnosticCollector, allocator: *Allocator) LirLowerer {}
    pub fn lowerFn(self: *LirLowerer, fn_node: u32) !LirFunction {}
    fn lowerExpr(self: *LirLowerer, node_idx: u32) !u32 {}
    fn lowerStmt(self: *LirLowerer, node_idx: u32) !void {}
    fn createBlock(self: *LirLowerer) u32 {}
    fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {}
    fn emitInst(self: *LirLowerer, inst: LirInst) !void {}
    fn expandDefers(self: *LirLowerer, target_depth: u32, is_error_path: bool) !void {}
    fn hoistTemps(self: *LirLowerer) void {}
    fn applyCoercion(self: *LirLowerer, src_temp: u32, coercion: CoercionEntry) !u32 {}
};

const std = @import("std");
const LirFunction = @import("lir.zig").LirFunction;
const LirInst = @import("lir.zig").LirInst;
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const ResolvedTypeTable = @import("semantic.zig").ResolvedTypeTable;
const CoercionTable = @import("semantic.zig").CoercionTable;
const CoercionEntry = @import("semantic.zig").CoercionEntry;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Allocator = @import("allocator.zig").Allocator;
