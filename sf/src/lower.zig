const LirFunction = @import("lir.zig").LirFunction;
const LirInst = @import("lir.zig").LirInst;
const BasicBlock = @import("lir.zig").BasicBlock;
const TempDecl = @import("lir.zig").TempDecl;
const TempDeclArrayList = @import("lir.zig").TempDeclArrayList;
const lir_mod = @import("lir.zig");
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstNode = @import("ast.zig").AstNode;
const AstKind = @import("ast.zig").AstKind;
const ast_mod = @import("ast.zig");
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const type_mod = @import("type_registry.zig");
const FieldEntry = @import("type_registry.zig").FieldEntry;
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const resolved_mod = @import("resolved_type_table.zig");
const CoercionTable = @import("coercion.zig").CoercionTable;
const CoercionEntry = @import("coercion.zig").CoercionEntry;
const CoercionKind = @import("coercion.zig").CoercionKind;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

const BIN_ADD  = @intCast(u8, 0);
const BIN_SUB  = @intCast(u8, 1);
const BIN_MUL  = @intCast(u8, 2);
const BIN_DIV  = @intCast(u8, 3);
const BIN_MOD  = @intCast(u8, 4);
const BIN_AND  = @intCast(u8, 5);
const BIN_OR   = @intCast(u8, 6);
const BIN_XOR  = @intCast(u8, 7);
const BIN_SHL  = @intCast(u8, 8);
const BIN_SHR  = @intCast(u8, 9);
const BIN_EQ   = @intCast(u8, 10);
const BIN_NE   = @intCast(u8, 11);
const BIN_LT   = @intCast(u8, 12);
const BIN_LE   = @intCast(u8, 13);
const BIN_GT   = @intCast(u8, 14);
const BIN_GE   = @intCast(u8, 15);
const UN_NEG   = @intCast(u8, 0);
const UN_NOT   = @intCast(u8, 1);
const UN_BNOT  = @intCast(u8, 2);

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

pub fn emitInst(self: *LirLowerer, inst: LirInst) void {
    lir_mod.lirInstArrayListAppend(&self.func.blocks.items[self.current_bb].insts, inst);
}

pub fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    var tid = self.temp_counter;
    self.temp_counter += 1;
    emitInst(self, LirInst{ .decl_temp = .{ .temp = tid, .type_id = type_id } });
    return tid;
}

pub fn lowerExpr(self: *LirLowerer, node_idx: u32) u32 {
    var node = self.ctx.store.nodes.items[@intCast(usize, node_idx)];
    var store = self.ctx.store;
    if (node.kind == AstKind.int_literal) {
        var val = store.int_values.items[@intCast(usize, node.payload)];
        var tid = nextTemp(self, type_mod.TYPE_INT_LIT);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.float_literal) {
        var val = store.float_values.items[@intCast(usize, node.payload)];
        var tid = nextTemp(self, type_mod.TYPE_F64);
        emitInst(self, LirInst{ .float_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.string_literal) {
        var str_id = store.string_values.items[@intCast(usize, node.payload)];
        var tid = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .string_const = .{ .string_id = str_id, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.char_literal) {
        var val = store.int_values.items[@intCast(usize, node.payload)];
        var tid = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bool_literal) {
        var val = @intCast(u8, node.payload & @intCast(u32, 1));
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .bool_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.null_literal) {
        var tid = nextTemp(self, type_mod.TYPE_NULL);
        emitInst(self, LirInst{ .null_const = .{ .result = tid } });
        return tid;
    } else if (node.kind == AstKind.undefined_literal) {
        var tid = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .undefined_const = .{ .result = tid, .type_id = type_mod.TYPE_UNDEFINED } });
        return tid;
    } else if (node.kind == AstKind.enum_literal) {
        var val = @intCast(u64, node.payload);
        var tid = nextTemp(self, type_mod.TYPE_INT_LIT);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.error_literal) {
        var val = @intCast(u64, node.payload);
        var tid = nextTemp(self, type_mod.TYPE_INT_LIT);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.unreachable_expr) {
        emitInst(self, LirInst{ .nop = {} });
        self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated = @intCast(u8, 1);
        return @intCast(u32, 0);
    } else if (node.kind == AstKind.paren_expr) {
        return lowerExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        return @intCast(u32, 0);
    } else if (node.kind == AstKind.add) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.sub) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.mul) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MUL, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.div) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_DIV, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.mod_op) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MOD, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_and) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_or) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_OR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_xor) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XOR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.shl) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHL, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.shr) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_eq) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_EQ, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_ne) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_NE, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_lt) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_LT, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_le) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_LE, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_gt) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_GT, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_ge) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_GE, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.negate) {
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .unary = .{ .op = UN_NEG, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bool_not) {
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .unary = .{ .op = UN_NOT, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_not) {
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .unary = .{ .op = UN_BNOT, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.assign) {
        var dst = lowerExpr(self, node.child_0);
        var src = lowerExpr(self, node.child_1);
        emitInst(self, LirInst{ .assign = .{ .dst = dst, .src = src } });
        return src;
    } else if (node.kind == AstKind.deref) {
        var ptr_temp = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .load = .{ .ptr = ptr_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.address_of) {
        var operand_temp = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .addr_of = .{ .operand = operand_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.index_access) {
        var base_temp = lowerExpr(self, node.child_0);
        var idx_temp = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .load_index = .{ .base = base_temp, .index = idx_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.ident_expr) {
        var name_id = store.identifiers.items[@intCast(usize, node.payload)];
        var tid = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .load_local = .{ .name_id = name_id, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.field_access) {
        var base_temp = lowerExpr(self, node.child_0);
        var field_name_id = store.identifiers.items[@intCast(usize, node.payload)];
        var resolved = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_U32);
        if (resolved) |type_id| {
            var ty = self.ctx.registry.types_items[@intCast(usize, type_id)];
            var kind = ty.kind;
            if (kind == type_mod.TypeKind.struct_type or kind == type_mod.TypeKind.union_type or kind == type_mod.TypeKind.tagged_union_type) {
                var fields: []FieldEntry = undefined;
                type_mod.typeRegistryGetStructFields(self.ctx.registry, type_id, &fields);
                var fi: usize = 0;
                while (fi < fields.len) : (fi += 1) {
                    if (fields[fi].name_id == field_name_id) {
                        emitInst(self, LirInst{ .load_field = .{ .base = base_temp, .field_id = @intCast(u32, fi), .result = tid } });
                        return tid;
                    }
                }
            }
        }
        return tid;
    } else if (node.kind == AstKind.fn_call) {
        var callee_temp = lowerExpr(self, node.child_0);
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var args_start = self.temp_counter;
        var i: usize = 0;
        while (i < ec.len) : (i += 1) {
            _ = lowerExpr(self, ec[i]);
        }
        var args_count = self.temp_counter - args_start;
        var result = nextTemp(self, type_mod.TYPE_I32);
        emitInst(self, LirInst{ .call = .{
            .callee = callee_temp,
            .args_start = args_start,
            .args_count = args_count,
            .result = result,
        } });
        return result;
    } else if (node.kind == AstKind.builtin_call) {
        return @intCast(u32, 0);
    } else {
        return @intCast(u32, 0);
    }
}

pub fn lowerStmt(self: *LirLowerer, node_idx: u32) void {
    _ = self;
    _ = node_idx;
}

pub fn createBlock(self: *LirLowerer) u32 {
    var id = self.func.blocks.len;
    var bb = BasicBlock{
        .id = @intCast(u32, id),
        .insts = lir_mod.lirInstArrayListInit(self.alloc),
        .is_terminated = @intCast(u8, 0),
    };
    lir_mod.basicBlockArrayListAppend(&self.func.blocks, bb);
    return @intCast(u32, id);
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
