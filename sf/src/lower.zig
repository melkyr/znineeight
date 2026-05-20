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
const coercion_mod = @import("coercion.zig");
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
    scope_depth: u32,
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
        .hoisted_temps = lir_mod.tempDeclArrayListInit(alloc),
        .alloc = alloc,
        .scope_depth = @intCast(u32, 0),
    };
}

pub fn emitInst(self: *LirLowerer, inst: LirInst) void {
    lir_mod.lirInstArrayListAppend(&self.func.blocks.items[self.current_bb].insts, inst);
}

pub fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    var tid = self.temp_counter;
    self.temp_counter += @intCast(u32, 1);
    lir_mod.tempDeclArrayListAppend(&self.hoisted_temps, TempDecl{
        .temp_id = tid,
        .type_id = type_id,
    });
    return tid;
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

fn lowerPrintCall(self: *LirLowerer, ec: []const u32) u32 {
    var store = self.ctx.store;
    var fmt_node = store.nodes.items[@intCast(usize, ec[0])];
    var string_id = store.identifiers.items[@intCast(usize, fmt_node.payload)];
    emitInst(self, LirInst{ .print_str = .{ .string_id = string_id } });
    var tuple_node = store.nodes.items[@intCast(usize, ec[1])];
    var tuple_ec = ast_mod.astStoreGetExtraChildren(store, tuple_node.payload);
    var i: usize = 0;
    while (i < tuple_ec.len) : (i += 1) {
        var val = lowerExpr(self, tuple_ec[i]);
        emitInst(self, LirInst{ .print_val = .{ .value = val, .type_id = type_mod.TYPE_I32, .fmt = @intCast(u8, 'd') } });
    }
    return @intCast(u32, 0);
}

pub fn lowerExpr(self: *LirLowerer, node_idx: u32) u32 {
    var result = lowerExprImpl(self, node_idx);
    return result;
}

fn lowerExprImpl(self: *LirLowerer, node_idx: u32) u32 {
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
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        if (ec.len >= @intCast(usize, 2)) {
            var first = store.nodes.items[@intCast(usize, ec[0])];
            var second = store.nodes.items[@intCast(usize, ec[1])];
            if (first.kind == AstKind.string_literal and second.kind == AstKind.tuple_literal) {
                return lowerPrintCall(self, ec);
            }
        }
        var callee_temp = lowerExpr(self, node.child_0);
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
    } else if (node.kind == AstKind.try_expr) {
        var inner_temp = lowerExpr(self, node.child_0);
        var is_err_temp = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .check_error = .{ .value = inner_temp, .result = is_err_temp } });
        var err_bb = createBlock(self);
        var ok_bb = createBlock(self);
        var join_bb = createBlock(self);
        emitInst(self, LirInst{ .branch = .{ .cond = is_err_temp, .then_bb = err_bb, .else_bb = ok_bb } });
        self.current_bb = err_bb;
        expandDefers(self, @intCast(u32, 0), @intCast(u8, 1));
        emitInst(self, LirInst{ .ret = inner_temp });
        self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated = @intCast(u8, 1);
        self.current_bb = ok_bb;
        var result = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = inner_temp, .result = result } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        return result;
    } else if (node.kind == AstKind.catch_expr) {
        var lhs_temp = lowerExpr(self, node.child_0);
        var is_err_temp = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .check_error = .{ .value = lhs_temp, .result = is_err_temp } });
        var err_bb = createBlock(self);
        var ok_bb = createBlock(self);
        var join_bb = createBlock(self);
        emitInst(self, LirInst{ .branch = .{ .cond = is_err_temp, .then_bb = err_bb, .else_bb = ok_bb } });
        var join_temp = nextTemp(self, type_mod.TYPE_UNDEFINED);
        self.current_bb = err_bb;
        var err_val = lowerExpr(self, node.child_1);
        emitInst(self, LirInst{ .assign = .{ .dst = join_temp, .src = err_val } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = ok_bb;
        var ok_val = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = lhs_temp, .result = ok_val } });
        emitInst(self, LirInst{ .assign = .{ .dst = join_temp, .src = ok_val } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        return join_temp;
    } else if (node.kind == AstKind.orelse_expr) {
        var lhs_temp = lowerExpr(self, node.child_0);
        var has_val_temp = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .check_optional = .{ .value = lhs_temp, .result = has_val_temp } });
        var null_bb = createBlock(self);
        var ok_bb = createBlock(self);
        var join_bb = createBlock(self);
        emitInst(self, LirInst{ .branch = .{ .cond = has_val_temp, .then_bb = ok_bb, .else_bb = null_bb } });
        var join_temp = nextTemp(self, type_mod.TYPE_UNDEFINED);
        self.current_bb = null_bb;
        var null_val = lowerExpr(self, node.child_1);
        emitInst(self, LirInst{ .assign = .{ .dst = join_temp, .src = null_val } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = ok_bb;
        var ok_val = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_optional = .{ .value = lhs_temp, .result = ok_val } });
        emitInst(self, LirInst{ .assign = .{ .dst = join_temp, .src = ok_val } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        return join_temp;
    } else if (node.kind == AstKind.if_expr) {
        var cond_temp = lowerExpr(self, node.child_0);
        var result = nextTemp(self, type_mod.TYPE_UNDEFINED);
        var then_bb = createBlock(self);
        var else_bb = createBlock(self);
        var join_bb = createBlock(self);
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = then_bb, .else_bb = else_bb } });
        self.current_bb = then_bb;
        var then_val = lowerExpr(self, node.child_1);
        emitInst(self, LirInst{ .assign = .{ .dst = result, .src = then_val } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = else_bb;
        var else_val = lowerExpr(self, node.child_2);
        emitInst(self, LirInst{ .assign = .{ .dst = result, .src = else_val } });
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        return result;
    } else if (node.kind == AstKind.switch_expr) {
        return @intCast(u32, 0);
    } else {
        return @intCast(u32, 0);
    }
}

fn lowerStmtBody(self: *LirLowerer, node_idx: u32) void {
    self.scope_depth += @intCast(u32, 1);
    var node = self.ctx.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.block) {
        var ec = ast_mod.astStoreGetExtraChildren(self.ctx.store, node.payload);
        var i: usize = 0;
        while (i < ec.len) : (i += 1) {
            lowerStmt(self, ec[i]);
        }
    } else {
        _ = lowerExpr(self, node_idx);
    }
    expandDefers(self, self.scope_depth, @intCast(u8, 0));
    self.scope_depth -= @intCast(u32, 1);
}

pub fn lowerStmt(self: *LirLowerer, node_idx: u32) void {
    var node = self.ctx.store.nodes.items[@intCast(usize, node_idx)];
    var store = self.ctx.store;
    if (node.kind == AstKind.block) {
        self.scope_depth += @intCast(u32, 1);
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var i: usize = 0;
        while (i < ec.len) : (i += 1) {
            lowerStmt(self, ec[i]);
        }
        expandDefers(self, self.scope_depth, @intCast(u8, 0));
        self.scope_depth -= @intCast(u32, 1);
    } else if (node.kind == AstKind.defer_stmt) {
        pushDefer(self, @intCast(u8, 0), node.child_0);
    } else if (node.kind == AstKind.errdefer_stmt) {
        pushDefer(self, @intCast(u8, 1), node.child_0);
    } else if (node.kind == AstKind.if_stmt) {
        var cond_temp = lowerExpr(self, node.child_0);
        var then_bb = createBlock(self);
        var else_bb: u32 = 0;
        var join_bb = createBlock(self);
        if (node.child_2 != 0) {
            else_bb = createBlock(self);
        }
        var fallthrough = if (else_bb != 0) else_bb else join_bb;
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = then_bb, .else_bb = fallthrough } });
        self.current_bb = then_bb;
        lowerStmtBody(self, node.child_1);
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        if (else_bb != 0) {
            self.current_bb = else_bb;
            lowerStmtBody(self, node.child_2);
            if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
                emitInst(self, LirInst{ .jump = join_bb });
            }
        }
        self.current_bb = join_bb;
    } else if (node.kind == AstKind.while_stmt) {
        var cond_bb = createBlock(self);
        var body_bb = createBlock(self);
        var exit_bb = createBlock(self);
        var loop_info = LoopInfo{
            .header_bb = cond_bb,
            .exit_bb = exit_bb,
            .scope_depth = self.scope_depth,
            .label_id = @intCast(u32, 0),
        };
        loopInfoArrayListAppend(&self.loop_stack, loop_info);
        emitInst(self, LirInst{ .jump = cond_bb });
        self.current_bb = cond_bb;
        var cond_temp = lowerExpr(self, node.child_0);
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = body_bb, .else_bb = exit_bb } });
        self.current_bb = body_bb;
        lowerStmtBody(self, node.child_1);
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = cond_bb });
        }
        self.current_bb = exit_bb;
        self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
    } else if (node.kind == AstKind.for_stmt) {
        var pattern = store.nodes.items[@intCast(usize, node.child_0)];
        if (node.child_2 != @intCast(u32, 0)) {
            var slice_temp = lowerExpr(self, node.child_0);
            var ptr_temp = nextTemp(self, type_mod.TYPE_U32);
            var len_temp = nextTemp(self, type_mod.TYPE_U32);
            emitInst(self, LirInst{ .load_field = .{ .base = slice_temp, .field_id = @intCast(u32, 0), .result = ptr_temp } });
            emitInst(self, LirInst{ .load_field = .{ .base = slice_temp, .field_id = @intCast(u32, 1), .result = len_temp } });
            var idx_temp = nextTemp(self, type_mod.TYPE_U32);
            emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = idx_temp } });
            var cond_bb = createBlock(self);
            var body_bb = createBlock(self);
            var exit_bb = createBlock(self);
            var loop_info = LoopInfo{ .header_bb = cond_bb, .exit_bb = exit_bb, .scope_depth = self.scope_depth, .label_id = @intCast(u32, 0) };
            loopInfoArrayListAppend(&self.loop_stack, loop_info);
            emitInst(self, LirInst{ .jump = cond_bb });
            self.current_bb = cond_bb;
            var cmp_temp = nextTemp(self, type_mod.TYPE_BOOL);
            emitInst(self, LirInst{ .binary = .{ .op = BIN_LT, .lhs = idx_temp, .rhs = len_temp, .result = cmp_temp } });
            emitInst(self, LirInst{ .branch = .{ .cond = cmp_temp, .then_bb = body_bb, .else_bb = exit_bb } });
            self.current_bb = body_bb;
            var item_temp = nextTemp(self, type_mod.TYPE_U32);
            emitInst(self, LirInst{ .load_index = .{ .base = ptr_temp, .index = idx_temp, .result = item_temp } });
            lowerStmtBody(self, node.child_1);
            if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
                var nxt_idx = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = idx_temp, .rhs = @intCast(u32, 1), .result = nxt_idx } });
                idx_temp = nxt_idx;
                emitInst(self, LirInst{ .jump = cond_bb });
            }
            self.current_bb = exit_bb;
            self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
    } else if (node.kind == AstKind.switch_expr) {
        var cond_temp = lowerExpr(self, node.child_0);
        var prong_ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var switch_bb = self.current_bb;
        var prong_start = @intCast(u32, self.func.blocks.len);
        var pi: usize = 0;
        while (pi < prong_ec.len) : (pi += 1) { _ = createBlock(self); }
        var else_bb = createBlock(self);
        var exit_bb = createBlock(self);
        var cases_start = @intCast(u32, self.func.switch_cases.len);
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = store.nodes.items[@intCast(usize, prong_ec[pi])];
            if (prong_node.flags & @intCast(u8, 1) != @intCast(u8, 0)) { continue; }
            var prong_bb_id = prong_start + @intCast(u32, pi);
            var case_ec = ast_mod.astStoreGetExtraChildren(store, prong_node.payload);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                var case_node = store.nodes.items[@intCast(usize, case_ec[ci])];
                var case_val: u64 = @intCast(u64, 0);
                if (case_node.kind == AstKind.int_literal) {
                    case_val = store.int_values.items[@intCast(usize, case_node.payload)];
                } else if (case_node.kind == AstKind.enum_literal) {
                    case_val = @intCast(u64, store.identifiers.items[@intCast(usize, case_node.payload)]);
                } else {
                    continue;
                }
                lir_mod.switchCaseArrayListAppend(&self.func.switch_cases,
                    lir_mod.SwitchCase{ .value = case_val, .target_bb = prong_bb_id });
            }
        }
        var sc_len = @intCast(u32, self.func.switch_cases.len);
        var cases_count: u32 = sc_len - cases_start;
        var else_target = else_bb;
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = store.nodes.items[@intCast(usize, prong_ec[pi])];
            if (prong_node.flags & @intCast(u8, 1) != @intCast(u8, 0)) {
                else_target = prong_start + @intCast(u32, pi);
                break;
            }
        }
        self.current_bb = switch_bb;
        emitInst(self, LirInst{ .switch_br = .{ .cond = cond_temp, .cases_start = cases_start, .cases_count = cases_count, .else_bb = else_target } });
        if (else_target == else_bb) {
            self.current_bb = else_bb;
            emitInst(self, LirInst{ .nop = {} });
            self.func.blocks.items[@intCast(usize, else_bb)].is_terminated = @intCast(u8, 1);
        }
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = store.nodes.items[@intCast(usize, prong_ec[pi])];
            var prong_bb_id = prong_start + @intCast(u32, pi);
            self.current_bb = prong_bb_id;
            lowerStmtBody(self, prong_node.child_0);
            if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
                emitInst(self, LirInst{ .jump = exit_bb });
            }
        }
        self.current_bb = exit_bb;
    } else {
            var start_temp = lowerExpr(self, pattern.child_0);
            var end_temp = lowerExpr(self, pattern.child_1);
            var cond_bb = createBlock(self);
            var body_bb = createBlock(self);
            var exit_bb = createBlock(self);
            var loop_info = LoopInfo{ .header_bb = cond_bb, .exit_bb = exit_bb, .scope_depth = self.scope_depth, .label_id = @intCast(u32, 0) };
            loopInfoArrayListAppend(&self.loop_stack, loop_info);
            emitInst(self, LirInst{ .jump = cond_bb });
            self.current_bb = cond_bb;
            var cmp_op = if (pattern.kind == AstKind.range_inclusive) BIN_LE else BIN_LT;
            var cmp_temp = nextTemp(self, type_mod.TYPE_BOOL);
            emitInst(self, LirInst{ .binary = .{ .op = cmp_op, .lhs = start_temp, .rhs = end_temp, .result = cmp_temp } });
            emitInst(self, LirInst{ .branch = .{ .cond = cmp_temp, .then_bb = body_bb, .else_bb = exit_bb } });
            self.current_bb = body_bb;
            lowerStmtBody(self, node.child_1);
            if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
                var nxt = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = start_temp, .rhs = @intCast(u32, 1), .result = nxt } });
                start_temp = nxt;
                emitInst(self, LirInst{ .jump = cond_bb });
            }
            self.current_bb = exit_bb;
            self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
        }
    } else if (node.kind == AstKind.return_stmt) {
        expandDefers(self, @intCast(u32, 0), @intCast(u8, 0));
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            if (node.child_0 != 0) {
                var val = lowerExpr(self, node.child_0);
                emitInst(self, LirInst{ .ret = val });
            } else {
                emitInst(self, LirInst{ .ret_void = {} });
            }
            self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated = @intCast(u8, 1);
        }
    } else if (node.kind == AstKind.break_stmt) {
        if (self.loop_stack.len == @intCast(usize, 0)) { return; }
        var label_id = node.payload;
        var exit_target: u32 = @intCast(u32, 0);
        var exit_scope: u32 = @intCast(u32, 0);
        if (label_id == @intCast(u32, 0)) {
            var li = self.loop_stack.items[self.loop_stack.len - @intCast(usize, 1)];
            exit_target = li.exit_bb;
            exit_scope = li.scope_depth + @intCast(u32, 1);
        } else {
            var si: usize = self.loop_stack.len;
            while (si > @intCast(usize, 0)) : (si -= @intCast(usize, 1)) {
                var li = self.loop_stack.items[si - @intCast(usize, 1)];
                if (li.label_id == label_id) {
                    exit_target = li.exit_bb;
                    exit_scope = li.scope_depth + @intCast(u32, 1);
                    break;
                }
            }
            if (exit_target == @intCast(u32, 0)) { return; }
        }
        expandDefers(self, exit_scope, @intCast(u8, 0));
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = exit_target });
            self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated = @intCast(u8, 1);
        }
    } else if (node.kind == AstKind.continue_stmt) {
        if (self.loop_stack.len == @intCast(usize, 0)) { return; }
        var label_id = node.payload;
        var header_target: u32 = @intCast(u32, 0);
        var cont_scope: u32 = @intCast(u32, 0);
        if (label_id == @intCast(u32, 0)) {
            var li = self.loop_stack.items[self.loop_stack.len - @intCast(usize, 1)];
            header_target = li.header_bb;
            cont_scope = li.scope_depth + @intCast(u32, 1);
        } else {
            var si: usize = self.loop_stack.len;
            while (si > @intCast(usize, 0)) : (si -= @intCast(usize, 1)) {
                var li = self.loop_stack.items[si - @intCast(usize, 1)];
                if (li.label_id == label_id) {
                    header_target = li.header_bb;
                    cont_scope = li.scope_depth + @intCast(u32, 1);
                    break;
                }
            }
            if (header_target == @intCast(u32, 0)) { return; }
        }
        expandDefers(self, cont_scope, @intCast(u8, 0));
        if (self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated == 0) {
            emitInst(self, LirInst{ .jump = header_target });
            self.func.blocks.items[@intCast(usize, self.current_bb)].is_terminated = @intCast(u8, 1);
        }
    } else {
        _ = self;
    }
}

pub fn pushDefer(self: *LirLowerer, kind: u8, ast_node: u32) void {
    deferActionArrayListAppend(&self.defer_stack, DeferAction{
        .kind = kind,
        .ast_node = ast_node,
        .scope_depth = self.scope_depth,
    });
}

pub fn expandDefers(self: *LirLowerer, target_depth: u32, is_error_path: u8) void {
    var i = self.defer_stack.len;
    while (i > @intCast(usize, 0)) {
        i -= @intCast(usize, 1);
        var action = self.defer_stack.items[i];
        if (action.scope_depth < target_depth) {
            break;
        }
        if (action.kind == @intCast(u8, 0)) {
            self.defer_stack.len = i;
            lowerStmt(self, action.ast_node);
            i = self.defer_stack.len;
        } else if (action.kind == @intCast(u8, 1) and is_error_path != @intCast(u8, 0)) {
            self.defer_stack.len = i;
            lowerStmt(self, action.ast_node);
            i = self.defer_stack.len;
        }
    }
}

pub fn hoistTemps(self: *LirLowerer) void {
    if (self.hoisted_temps.len == @intCast(usize, 0)) return;
    var entry_bb = &self.func.blocks.items[@intCast(usize, 0)];
    var new_insts = lir_mod.lirInstArrayListInit(self.alloc);
    var i: usize = 0;
    while (i < self.hoisted_temps.len) : (i += 1) {
        var td = self.hoisted_temps.items[i];
        lir_mod.lirInstArrayListAppend(&new_insts, LirInst{
            .decl_temp = .{ .temp = td.temp_id, .type_id = td.type_id },
        });
    }
    var j: usize = 0;
    while (j < entry_bb.insts.len) : (j += 1) {
        lir_mod.lirInstArrayListAppend(&new_insts, entry_bb.insts.items[j]);
    }
    entry_bb.insts.items = new_insts.items;
    entry_bb.insts.len = new_insts.len;
    entry_bb.insts.capacity = new_insts.capacity;
}

pub fn applyCoercion(self: *LirLowerer, src_temp: u32, coercion: CoercionEntry) u32 {
    var kind = coercion.kind;
    if (kind == CoercionKind.none) {
        return src_temp;
    } else if (kind == CoercionKind.wrap_optional) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .wrap_optional = .{ .value = src_temp, .result = dst, .type_id = coercion.target_type } });
        return dst;
    } else if (kind == CoercionKind.wrap_error_success) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .wrap_error_ok = .{ .value = src_temp, .result = dst, .type_id = coercion.target_type } });
        return dst;
    } else if (kind == CoercionKind.wrap_error_err) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .wrap_error_err = .{ .value = src_temp, .result = dst, .type_id = coercion.target_type } });
        return dst;
    } else if (kind == CoercionKind.int_widen) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .int_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst, .is_checked = @intCast(u8, 0) } });
        return dst;
    } else if (kind == CoercionKind.float_widen) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .float_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst } });
        return dst;
    } else if (kind == CoercionKind.int_literal_coerce) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .int_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst, .is_checked = @intCast(u8, 0) } });
        return dst;
    } else if (kind == CoercionKind.ptr_to_optional_ptr) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .wrap_optional = .{ .value = src_temp, .result = dst, .type_id = coercion.target_type } });
        return dst;
    } else if (kind == CoercionKind.array_to_slice) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .make_slice = .{ .ptr = src_temp, .len = @intCast(u32, 1), .result = dst, .type_id = coercion.target_type } });
        return dst;
    } else if (kind == CoercionKind.array_to_many_ptr) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .ptr_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst } });
        return dst;
    } else if (kind == CoercionKind.slice_to_many_ptr) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .ptr_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst } });
        return dst;
    } else if (kind == CoercionKind.string_to_slice) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .make_slice = .{ .ptr = src_temp, .len = @intCast(u32, 1), .result = dst, .type_id = coercion.target_type } });
        return dst;
    } else if (kind == CoercionKind.string_to_many_ptr) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .ptr_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst } });
        return dst;
    } else if (kind == CoercionKind.string_to_ptr) {
        var dst = nextTemp(self, coercion.target_type);
        emitInst(self, LirInst{ .ptr_cast = .{ .value = src_temp, .target = coercion.target_type, .result = dst } });
        return dst;
    } else if (kind == CoercionKind.const_qualify) {
        return src_temp;
    } else if (kind == CoercionKind.unwrap_optional) {
        return src_temp;
    } else {
        return src_temp;
    }
}

pub fn lowerFn(self: *LirLowerer, fn_node: u32) LirFunction {
    var store = self.ctx.store;
    var node = store.nodes.items[@intCast(usize, fn_node)];
    var proto_idx = node.payload;
    var proto = store.fn_protos.items[@intCast(usize, proto_idx)];
    var func_raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, @sizeOf(LirFunction)), @intCast(usize, 4)) catch unreachable;
    var func_ptr = @ptrCast(*LirFunction, func_raw);
    func_ptr.name_id = proto.name_id;
    func_ptr.return_type = type_mod.TYPE_VOID;
    func_ptr.params = lir_mod.lirParamArrayListInit(self.alloc);
    func_ptr.blocks = lir_mod.basicBlockArrayListInit(self.alloc);
    func_ptr.hoisted_temps = lir_mod.tempDeclArrayListInit(self.alloc);
    func_ptr.switch_cases = lir_mod.switchCaseArrayListInit(self.alloc);
    func_ptr.is_extern = @intCast(u8, 0);
    func_ptr.is_pub = @intCast(u8, 0);
    self.func = func_ptr;
    self.current_bb = createBlock(self);
    self.scope_depth = @intCast(u32, 0);
    self.temp_counter = @intCast(u32, 0);
    var body = node.child_0;
    if (body != 0) {
        lowerStmtBody(self, body);
    }
    expandDefers(self, @intCast(u32, 0), @intCast(u8, 0));
    if (self.func.blocks.items[@intCast(usize, 0)].is_terminated == @intCast(u8, 0)) {
        emitInst(self, LirInst{ .ret_void = {} });
    }
    hoistTemps(self);
    return func_ptr.*;
}
