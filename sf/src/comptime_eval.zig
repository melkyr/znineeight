pub const ComptimeEval = struct {
    value_table: U32ToU64Map,
    registry: *TypeRegistry,
    interner: *StringInterner,
    allocator: *Allocator,

    pub fn init(registry: *TypeRegistry, interner: *StringInterner, allocator: *Allocator) ComptimeEval {}
    pub fn evaluate(self: *ComptimeEval, store: *AstStore, node_idx: u32) ?u64 {}
    fn evalBuiltin(self: *ComptimeEval, store: *AstStore, node: AstNode) ?u64 {}
    fn evalBinOp(self: *ComptimeEval, store: *AstStore, node: AstNode, op: AstKind) ?u64 {}
    fn evalIdent(self: *ComptimeEval, store: *AstStore, node: AstNode) ?u64 {}
};

pub const U32ToU64Map = struct {
    keys: []u32,
    values: []u64,
    occupied: []bool,
    capacity: u32,
    count: u32,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator, capacity: u32) U32ToU64Map {}
    pub fn get(self: *U32ToU64Map, key: u32) ?u64 {}
    pub fn put(self: *U32ToU64Map, key: u32, value: u64) !void {}
};

const std = @import("std");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const StringInterner = @import("string_interner.zig").StringInterner;
const AstStore = @import("ast.zig").AstStore;
const AstNode = @import("ast.zig").AstNode;
const AstKind = @import("ast.zig").AstKind;
const Allocator = @import("allocator.zig").Allocator;
