pub const DepEntry = struct {
    source: TypeId,
    target: TypeId,
};

pub const TypeResolver = struct {
    registry: *TypeRegistry,
    dependents: std.ArrayList(DepEntry),
    in_degree: []u32,
    worklist: std.ArrayList(TypeId),
    diag: *DiagnosticCollector,
    allocator: *Allocator,

    pub fn init(registry: *TypeRegistry, diag: *DiagnosticCollector, allocator: *Allocator) TypeResolver {}
    pub fn addDependency(self: *TypeResolver, source: TypeId, target: TypeId) !void {}
    pub fn resolve(self: *TypeResolver) !void {}
    fn resolveTypeLayout(self: *TypeResolver, tid: TypeId) !void {}
};

const std = @import("std");
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
