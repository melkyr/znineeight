pub const Symbol = struct {
    name_id: u32,
    type_id: u32,
    kind: u8,
    flags: u16,
    decl_node: u32,
    module_id: u32,
    scope_level: u32,
};

pub const Scope = struct {
    parent: u32,
    symbols: std.ArrayList(Symbol),
};

pub const SymbolTable = struct {
    scopes: std.ArrayList(Scope),
    current_scope: u32,
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) SymbolTable {}
    pub fn enterScope(self: *SymbolTable) !u32 {}
    pub fn leaveScope(self: *SymbolTable) void {}
    pub fn insert(self: *SymbolTable, sym: Symbol) !void {}
    pub fn lookup(self: *SymbolTable, name_id: u32) ?*Symbol {}
};

pub const SymbolKind = enum(u8) {
    local = 0,
    param = 1,
    global = 2,
    function = 3,
    type_alias = 4,
    module = 5,
    test_sym = 6,
};

pub const SymbolRegistry = struct {
    tables: std.ArrayList(SymbolTable),
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) SymbolRegistry {}
    pub fn getTable(self: *SymbolRegistry, module_id: u32) *SymbolTable {}
};

const std = @import("std");
const Allocator = @import("allocator.zig").Allocator;
