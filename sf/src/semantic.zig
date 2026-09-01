pub const ResolvedTypeTable = struct {
    entries: std.ArrayList(ResolvedTypeEntry),
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) ResolvedTypeTable {}
    pub fn set(self: *ResolvedTypeTable, node_idx: u32, type_id: TypeId) !void {}
    pub fn get(self: *ResolvedTypeTable, node_idx: u32) ?TypeId {}
};

pub const ResolvedTypeEntry = struct {
    node_idx: u32,
    type_id: TypeId,
};

pub const CoercionKind = enum(u8) {
    none,
    wrap_optional,
    wrap_error_success,
    wrap_error_err,
    unwrap_optional,
    array_to_slice,
    array_to_many_ptr,
    slice_to_many_ptr,
    string_to_slice,
    string_to_many_ptr,
    string_to_ptr,
    ptr_to_optional_ptr,
    const_qualify,
    int_widen,
    float_widen,
};

pub const CoercionEntry = struct {
    node_idx: u32,
    kind: CoercionKind,
    target_type: TypeId,
};

pub const CoercionTable = struct {
    entries: std.ArrayList(CoercionEntry),
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) CoercionTable {}
    pub fn add(self: *CoercionTable, node_idx: u32, kind: CoercionKind, target: TypeId) !void {}
    pub fn get(self: *CoercionTable, node_idx: u32) ?CoercionEntry {}
};

pub const SemanticAnalyzer = struct {
    resolved_types: ResolvedTypeTable,
    coercions: CoercionTable,
    registry: *TypeRegistry,
    interner: *StringInterner,
    symbol_tables: *SymbolRegistry,
    diag: *DiagnosticCollector,
    allocator: *Allocator,

    pub fn init(registry: *TypeRegistry, interner: *StringInterner, symbol_tables: *SymbolRegistry, diag: *DiagnosticCollector, allocator: *Allocator) SemanticAnalyzer {}
    pub fn analyzeModule(self: *SemanticAnalyzer, module_id: u32, store: *AstStore, root_node: u32) !void {}
    fn resolveExpr(self: *SemanticAnalyzer, store: *AstStore, node_idx: u32) !TypeId {}
    fn resolveFnCall(self: *SemanticAnalyzer, store: *AstStore, node: AstNode) !TypeId {}
    fn isAssignable(self: *SemanticAnalyzer, source: TypeId, target: TypeId) bool {}
    fn classifyCoercion(self: *SemanticAnalyzer, source: TypeId, target: TypeId) CoercionKind {}
};

const std = @import("std");
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const StringInterner = @import("string_interner.zig").StringInterner;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const AstStore = @import("ast.zig").AstStore;
const AstNode = @import("ast.zig").AstNode;
const Allocator = @import("allocator.zig").Allocator;
