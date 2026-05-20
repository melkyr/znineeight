const LirFunction = @import("lir.zig").LirFunction;
const LirInst = @import("lir.zig").LirInst;
const TempDecl = @import("lir.zig").TempDecl;
const TempDeclArrayList = @import("lir.zig").TempDeclArrayList;
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const CoercionTable = @import("coercion.zig").CoercionTable;
const CoercionEntry = @import("coercion.zig").CoercionEntry;
const CoercionKind = @import("coercion.zig").CoercionKind;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const DeferAction = struct {
    kind: u8,
    ast_node: u32,
    scope_depth: u32,
};

pub const LoopInfo = struct {
    header_bb: u32,
    exit_bb: u32,
    scope_depth: u32,
    label_id: u32,
};

pub const SwitchInfo = struct {
    exit_bb: u32,
    scope_depth: u32,
};

pub const SemanticContext = struct {
    store: *AstStore,
    registry: *TypeRegistry,
    symbol_tables: *SymbolRegistry,
    resolved_types: *ResolvedTypeTable,
    coercions: *CoercionTable,
    diag: *DiagnosticCollector,
};

pub const DeferActionArrayList = struct {
    items: [*]DeferAction,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn deferActionArrayListInit(allocator: *Sand) DeferActionArrayList {
    return DeferActionArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn deferActionArrayListEnsureCapacity(self: *DeferActionArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(DeferAction) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]DeferAction, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn deferActionArrayListAppend(self: *DeferActionArrayList, value: DeferAction) void {
    deferActionArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn deferActionArrayListGetSlice(self: *DeferActionArrayList) []DeferAction {
    return self.items[0..self.len];
}

pub const LoopInfoArrayList = struct {
    items: [*]LoopInfo,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn loopInfoArrayListInit(allocator: *Sand) LoopInfoArrayList {
    return LoopInfoArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn loopInfoArrayListEnsureCapacity(self: *LoopInfoArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(LoopInfo) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]LoopInfo, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn loopInfoArrayListAppend(self: *LoopInfoArrayList, value: LoopInfo) void {
    loopInfoArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn loopInfoArrayListGetSlice(self: *LoopInfoArrayList) []LoopInfo {
    return self.items[0..self.len];
}

pub const SwitchInfoArrayList = struct {
    items: [*]SwitchInfo,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn switchInfoArrayListInit(allocator: *Sand) SwitchInfoArrayList {
    return SwitchInfoArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn switchInfoArrayListEnsureCapacity(self: *SwitchInfoArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(SwitchInfo) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]SwitchInfo, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn switchInfoArrayListAppend(self: *SwitchInfoArrayList, value: SwitchInfo) void {
    switchInfoArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn switchInfoArrayListGetSlice(self: *SwitchInfoArrayList) []SwitchInfo {
    return self.items[0..self.len];
}

pub const LirLowerer = struct {
    ctx: *SemanticContext,
    func: *LirFunction,
    current_bb: u32,
    temp_counter: u32,
    defer_stack: DeferActionArrayList,
    loop_stack: LoopInfoArrayList,
    switch_stack: SwitchInfoArrayList,
    hoisted_temps: TempDeclArrayList,
    alloc: *Sand,
};

pub fn lowererInit(ctx: *SemanticContext, alloc: *Sand) LirLowerer {
    return LirLowerer{
        .ctx = ctx,
        .func = undefined,
        .current_bb = @intCast(u32, 0),
        .temp_counter = @intCast(u32, 0),
        .defer_stack = deferActionArrayListInit(alloc),
        .loop_stack = loopInfoArrayListInit(alloc),
        .switch_stack = switchInfoArrayListInit(alloc),
        .hoisted_temps = undefined,
        .alloc = alloc,
    };
}

pub fn lowerFn(self: *LirLowerer, fn_node: u32) LirFunction {
    _ = self;
    _ = fn_node;
    return undefined;
}

pub fn lowerExpr(self: *LirLowerer, node_idx: u32) u32 {
    _ = self;
    _ = node_idx;
    return @intCast(u32, 0);
}

pub fn lowerStmt(self: *LirLowerer, node_idx: u32) void {
    _ = self;
    _ = node_idx;
}

pub fn createBlock(self: *LirLowerer) u32 {
    _ = self;
    return @intCast(u32, 0);
}

pub fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    _ = self;
    _ = type_id;
    return @intCast(u32, 0);
}

pub fn emitInst(self: *LirLowerer, inst: LirInst) void {
    _ = self;
    _ = inst;
}

pub fn expandDefers(self: *LirLowerer, target_depth: u32, is_error_path: u8) void {
    _ = self;
    _ = target_depth;
    _ = is_error_path;
}

pub fn hoistTemps(self: *LirLowerer) void {
    _ = self;
}

pub fn applyCoercion(self: *LirLowerer, src_temp: u32, coercion: CoercionEntry) u32 {
    _ = self;
    _ = src_temp;
    _ = coercion;
    return @intCast(u32, 0);
}
