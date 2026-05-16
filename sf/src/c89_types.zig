pub const C89TypeEmitter = struct {
    writer: *BufferedWriter,
    registry: *TypeRegistry,
    interner: *StringInterner,
    mangler: *NameMangler,
    emitted: std.ArrayList(u8),

    pub fn init(writer: *BufferedWriter, registry: *TypeRegistry, interner: *StringInterner, mangler: *NameMangler, allocator: *Allocator) C89TypeEmitter {}
    pub fn emitSpecialTypes(self: *C89TypeEmitter, module_ids: []const u32) !void {}
    pub fn emitSliceType(self: *C89TypeEmitter, elem_name: []const u8, mangled_name: []const u8) !void {}
    pub fn emitOptionalType(self: *C89TypeEmitter, payload_name: []const u8, mangled_name: []const u8) !void {}
    pub fn emitErrorUnionType(self: *C89TypeEmitter, payload_name: []const u8, error_name: []const u8, mangled_name: []const u8) !void {}
    pub fn emitTaggedUnionType(self: *C89TypeEmitter, tid: TypeId) !void {}
};

const std = @import("std");
const BufferedWriter = @import("c89_emit.zig").BufferedWriter;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = @import("type_registry.zig").TypeId;
const StringInterner = @import("string_interner.zig").StringInterner;
const NameMangler = @import("c89_emit.zig").NameMangler;
const Allocator = @import("allocator.zig").Allocator;
