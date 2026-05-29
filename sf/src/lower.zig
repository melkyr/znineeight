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
const ModuleRegistry = @import("module_registry.zig").ModuleRegistry;
const pal = @import("pal.zig");
const sym_mod = @import("symbol_table.zig");
const Symbol = @import("symbol_table.zig").Symbol;
const si_mod = @import("string_interner.zig");
const format_mod = @import("util/format.zig");
const itoa_mod = @import("util/itoa.zig");
const hash_mod = @import("util/hash.zig");

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
    has_symbols: u8,
    enum_value_table: *hash_mod.U32ToU32Map,
    call_arg_types: *hash_mod.U32ToU32Map,
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

fn dbgPrintU32(val: u32) void {
    var buf: [20]u8 = undefined;
    var len = itoa_mod.itoa(val, buf[0..]);
    var sbase: usize = @intCast(usize, 19) - @intCast(usize, len);
    var send: usize = @intCast(usize, 19);
    pal.stderr_write(buf[sbase .. send]);
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
    block_terminated: u8,
    module_id: u32,
    module_reg: *ModuleRegistry,
    intcast_name_id: u32,
    inttofloat_name_id: u32,
    local_decl_names: [64]u32,
    local_decl_types: [64]u32,
    local_decl_temps: [64]u32,
    local_decl_count: usize,
    _fn_ret_type: u32,
};

pub fn lowererInit(ctx: *SemanticContext, alloc: *Sand) LirLowerer {
    var intcast_s: []const u8 = "@intCast";
    var intcast_id = si_mod.stringInternerIntern(ctx.registry.interner, intcast_s);
    var inttofloat_s: []const u8 = "@intToFloat";
    var inttofloat_id = si_mod.stringInternerIntern(ctx.registry.interner, inttofloat_s);
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
        .block_terminated = @intCast(u8, 0),
        .module_id = @intCast(u32, 0),
        .module_reg = undefined,
        .intcast_name_id = intcast_id,
        .inttofloat_name_id = inttofloat_id,
        .local_decl_names = undefined,
        .local_decl_types = undefined,
        .local_decl_temps = undefined,
        .local_decl_count = @intCast(usize, 0),
        ._fn_ret_type = @intCast(u32, 0),
    };
}

fn markTerminated(blocks: *lir_mod.BasicBlockArrayList, bb_id: u32) void {
    var ms: []const u8 = "MT"; pal.stderr_write(ms);
    var b = &blocks.items[@intCast(usize, bb_id)];
    b.is_terminated = @intCast(u8, 1);
    var me: []const u8 = "\n"; pal.stderr_write(me);
}

pub fn emitInst(self: *LirLowerer, inst: LirInst) void {
    lir_mod.lirInstArrayListAppend(&self.func.blocks.items[self.current_bb].insts, inst);
}

pub fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    var tid = self.temp_counter;
    if (type_id == type_mod.TYPE_UNDEFINED or type_id == type_mod.TYPE_VOID) {
        var nm: []const u8 = "N"; pal.stderr_write(nm);
        var ntb: [20]u8 = undefined; var ntl = itoa_mod.itoa(tid, ntb[0..]); var nts: usize = @intCast(usize, 19) - @intCast(usize, ntl); pal.stderr_write(ntb[nts..@intCast(usize, 19)]);
        var ntp: []const u8 = "t"; pal.stderr_write(ntp);
        var ntpb: [20]u8 = undefined; var ntpl = itoa_mod.itoa(type_id, ntpb[0..]); var ntps: usize = @intCast(usize, 19) - @intCast(usize, ntpl); pal.stderr_write(ntpb[ntps..@intCast(usize, 19)]);
        var nnl: []const u8 = " "; pal.stderr_write(nnl);
    }
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
    var string_id = fmt_node.payload;
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

fn addLocalDecl(self: *LirLowerer, name_id: u32, type_id: u32, temp: u32) void {
    if (self.local_decl_count >= @intCast(usize, 64)) return;
    self.local_decl_names[self.local_decl_count] = name_id;
    self.local_decl_types[self.local_decl_count] = type_id;
    self.local_decl_temps[self.local_decl_count] = temp;
    self.local_decl_count += @intCast(usize, 1);
}

fn findLocalTemp(self: *LirLowerer, name_id: u32) u32 {
    if (self.local_decl_count == @intCast(usize, 0)) return @intCast(u32, 0);
    var li: usize = @intCast(usize, 0);
    while (li < self.local_decl_count) : (li += @intCast(usize, 1)) {
        if (self.local_decl_names[li] == name_id) { return self.local_decl_temps[li]; }
    }
    return @intCast(u32, 0);
}

fn maybeExtractSlicePtr(self: *LirLowerer, base_node: u32, base_temp: u32) u32 {
    var resolved = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, base_node);
    if (resolved) |rt| {
        var rt_ty = self.ctx.registry.types_items[@intCast(usize, rt)];
        var mg1s: []const u8 = "MS:1\n"; pal.stderr_write(mg1s);
        if (rt_ty.kind == type_mod.TypeKind.slice_type) {
            var sp = self.ctx.registry.slice_items[@intCast(usize, rt_ty.payload_idx)];
            var ptr_type = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, sp.elem, false);
            var ptr_temp = nextTemp(self, ptr_type);
            emitInst(self, LirInst{ .load_field = .{ .base = base_temp, .field_id = @intCast(u32, 0), .result = ptr_temp } });
            return ptr_temp;
        }
    }
    return base_temp;
}

fn addLoopCapture(self: *LirLowerer, capture_node: u32, item_temp: u32) void {
    var cap = self.ctx.store.nodes.items[@intCast(usize, capture_node)];
    var l5s: []const u8 = "L5:1\n"; pal.stderr_write(l5s);
    addLocalDecl(self, cap.payload, type_mod.TYPE_U32, item_temp);
}

fn lowerGlobalRef(self: *LirLowerer, s: sym_mod.Symbol, name_id: u32) u32 {
    var lgr_m: []const u8 = "LGR:n"; pal.stderr_write(lgr_m);
    var lgr_b: [20]u8 = undefined; var lgr_l = itoa_mod.itoa(name_id, lgr_b[0..]); var lgr_s: usize = @intCast(usize, 19) - @intCast(usize, lgr_l); pal.stderr_write(lgr_b[lgr_s..@intCast(usize, 19)]);
    var lgr_nl: []const u8 = " "; pal.stderr_write(lgr_nl);
    var dn_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, s.decl_node);
    var tid_type = if (dn_type) |dt| dt else type_mod.TYPE_UNDEFINED;
    var tid = nextTemp(self, tid_type);
    emitInst(self, LirInst{ .decl_local = .{ .name_id = name_id, .type_id = tid_type, .temp = tid } });
    return tid;
}

fn lowerExprImpl(self: *LirLowerer, node_idx: u32) u32 {
    var blm: []const u8 = "GBL"; pal.stderr_write(blm);
    var node = self.ctx.store.nodes.items[@intCast(usize, node_idx)];
    var store = self.ctx.store;
    var t_target: u32 = @intCast(u32, 10);
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
        var ptr_type = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, type_mod.TYPE_C_CHAR, true);
        var tid = nextTemp(self, ptr_type);
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
        var ev_val: u64 = @intCast(u64, node.payload);
        var evptr: u32 = @intCast(u32, @ptrToInt(self.ctx.enum_value_table));
        var evpb: [20]u8 = undefined;
        var evpl = itoa_mod.itoa(evptr, evpb[0..]);
        var evps: usize = @intCast(usize, 19) - @intCast(usize, evpl);
        var evR: []const u8 = "ER"; pal.stderr_write(evR);
        pal.stderr_write(evpb[evps..@intCast(usize, 19)]);
        var evgc2 = self.ctx.enum_value_table.count;
        var eg2b: [20]u8 = undefined;
        var eg2l = itoa_mod.itoa(@intCast(u32, evgc2), eg2b[0..]);
        var eg2s: usize = @intCast(usize, 19) - @intCast(usize, eg2l);
        var eRc: []const u8 = "c="; pal.stderr_write(eRc);
        pal.stderr_write(eg2b[eg2s..@intCast(usize, 19)]);
        var eRs: []const u8 = " "; pal.stderr_write(eRs);
        var ev = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, node_idx);
        if (ev) |v| { ev_val = @intCast(u64, v); var we1: []const u8 = "WE"; pal.stderr_write(we1); }
        else { var we1: []const u8 = "wE"; pal.stderr_write(we1); }
        var tid = nextTemp(self, type_mod.TYPE_INT_LIT);
        emitInst(self, LirInst{ .int_const = .{ .value = ev_val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.error_literal) {
        var val = @intCast(u64, node.payload);
        var tid = nextTemp(self, type_mod.TYPE_INT_LIT);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.unreachable_expr) {
        emitInst(self, LirInst{ .nop = {} });
        self.block_terminated = @intCast(u8, 1);
        return @intCast(u32, 0);
    } else if (node.kind == AstKind.paren_expr) {
        return lowerExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        return @intCast(u32, 0);
    } else if (node.kind == AstKind.add) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.sub) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.mul) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MUL, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.div) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_DIV, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.mod_op) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MOD, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_and) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_or) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_OR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_xor) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XOR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.shl) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHL, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.shr) {
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        var tid = nextTemp(self, rtype);
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
    } else if (node.kind == AstKind.bool_or) {
        var lhs_tid = lowerExpr(self, node.child_0);
        var rhs_bb = createBlock(self);
        var true_bb = createBlock(self);
        var done_bb = createBlock(self);
        var result = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .branch = .{ .cond = lhs_tid, .then_bb = true_bb, .else_bb = rhs_bb } });
        self.current_bb = rhs_bb;
        self.block_terminated = @intCast(u8, 0);
        var rhs_tid = lowerExpr(self, node.child_1);
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .assign = .{ .dst = result, .src = rhs_tid } });
            emitInst(self, LirInst{ .jump = done_bb });
        }
        self.current_bb = true_bb;
        self.block_terminated = @intCast(u8, 0);
        emitInst(self, LirInst{ .bool_const = .{ .value = @intCast(u8, 1), .result = result } });
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = done_bb });
        }
        self.current_bb = done_bb;
        self.block_terminated = @intCast(u8, 0);
        return result;
    } else if (node.kind == AstKind.bool_and) {
        var lhs_tid = lowerExpr(self, node.child_0);
        var rhs_bb = createBlock(self);
        var false_bb = createBlock(self);
        var done_bb = createBlock(self);
        var result = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .branch = .{ .cond = lhs_tid, .then_bb = rhs_bb, .else_bb = false_bb } });
        self.current_bb = rhs_bb;
        self.block_terminated = @intCast(u8, 0);
        var rhs_tid = lowerExpr(self, node.child_1);
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .assign = .{ .dst = result, .src = rhs_tid } });
            emitInst(self, LirInst{ .jump = done_bb });
        }
        self.current_bb = false_bb;
        self.block_terminated = @intCast(u8, 0);
        emitInst(self, LirInst{ .bool_const = .{ .value = @intCast(u8, 0), .result = result } });
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = done_bb });
        }
        self.current_bb = done_bb;
        self.block_terminated = @intCast(u8, 0);
        return result;
    } else if (node.kind == AstKind.negate) {
        var val = lowerExpr(self, node.child_0);
        var rt_ng = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ng_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_ng) |t| { if (t != type_mod.TYPE_UNDEFINED) { ng_box[0] = t; } }
        var tid = nextTemp(self, ng_box[0]);
        emitInst(self, LirInst{ .unary = .{ .op = UN_NEG, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bool_not) {
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .unary = .{ .op = UN_NOT, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_not) {
        var val = lowerExpr(self, node.child_0);
        var rt_bn = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var bn_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_bn) |t| { if (t != type_mod.TYPE_UNDEFINED) { bn_box[0] = t; } }
        var tid = nextTemp(self, bn_box[0]);
        emitInst(self, LirInst{ .unary = .{ .op = UN_BNOT, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.assign) {
        var child_node = store.nodes.items[@intCast(usize, node.child_0)];
        var src = lowerExpr(self, node.child_1);
        if (child_node.kind == AstKind.ident_expr) {
            var name_id = store.identifiers.items[@intCast(usize, child_node.payload)];
            var gsym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, name_id);
            var gbuf: [20]u8 = undefined;
            var gh: []const u8 = "GL";
            pal.stderr_write(gh);
            if (gsym) |gs| {
                var gsk = itoa_mod.itoa(@intCast(u32, @enumToInt(gs.kind)), gbuf[0..]);
                var gsl: usize = @intCast(usize, gsk);
                var gss: usize = @intCast(usize, 20) - @intCast(usize, 1) - gsl;
                pal.stderr_write(gh);
                pal.stderr_write(gbuf[gss..@intCast(usize, 20)]);
            } else {
                var gtable = sym_mod.symbolRegistryGetTable(self.ctx.symbol_tables, self.module_id);
                var gtl = itoa_mod.itoa(@intCast(u32, gtable.len), gbuf[0..]);
                var gtsl: usize = @intCast(usize, gtl);
                var gtss: usize = @intCast(usize, 20) - @intCast(usize, 1) - gtsl;
                var gms: []const u8 = "M:";
                pal.stderr_write(gms);
                pal.stderr_write(gbuf[gtss..@intCast(usize, 20)]);
                var gnl = itoa_mod.itoa(name_id, gbuf[0..]);
                var gnsl: usize = @intCast(usize, gnl);
                var gnss: usize = @intCast(usize, 20) - @intCast(usize, 1) - gnsl;
                var gns: []const u8 = ":";
                pal.stderr_write(gns);
                pal.stderr_write(gbuf[gnss..@intCast(usize, 20)]);
                var gei: usize = @intCast(usize, 0);
                while (gei < @intCast(usize, gtable.len)) : (gei += @intCast(usize, 1)) {
                    var dent = gtable.items[gei];
                    var dn = itoa_mod.itoa(dent.name_id, gbuf[0..]);
                    var dnl: usize = @intCast(usize, dn);
                    var dns: usize = @intCast(usize, 20) - @intCast(usize, 1) - dnl;
                    var dq: []const u8 = ".";
                    pal.stderr_write(dq);
                    pal.stderr_write(gbuf[dns..@intCast(usize, 20)]);
                    var dk = itoa_mod.itoa(@intCast(u32, @enumToInt(dent.kind)), gbuf[0..]);
                    var dkl: usize = @intCast(usize, dk);
                    var dks: usize = @intCast(usize, 20) - @intCast(usize, 1) - dkl;
                    var dsp: []const u8 = ",";
                    pal.stderr_write(dsp);
                    pal.stderr_write(gbuf[dks..@intCast(usize, 20)]);
                }
                }
            var gn: []const u8 = "\n";
            pal.stderr_write(gn);
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = src } });
        } else if (child_node.kind == AstKind.index_access) {
            var base_temp = lowerExpr(self, child_node.child_0);
            base_temp = maybeExtractSlicePtr(self, child_node.child_0, base_temp);
            var idx_temp = lowerExpr(self, child_node.child_1);
            emitInst(self, LirInst{ .assign_index = .{ .base = base_temp, .index = idx_temp, .src = src } });
        } else {
            var dst = lowerExpr(self, node.child_0);
            emitInst(self, LirInst{ .assign = .{ .dst = dst, .src = src } });
        }
        return src;
    } else if (node.kind == AstKind.deref) {
        var ptr_temp = lowerExpr(self, node.child_0);
        var rt_dr = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var dr_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_dr) |t| { if (t != type_mod.TYPE_UNDEFINED) { dr_box[0] = t; } }
        var tid = nextTemp(self, dr_box[0]);
        emitInst(self, LirInst{ .load = .{ .ptr = ptr_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.address_of) {
        var child_node = store.nodes.items[@intCast(usize, node.child_0)];
        if (child_node.kind == AstKind.index_access) {
            var base_temp = lowerExpr(self, child_node.child_0);
            base_temp = maybeExtractSlicePtr(self, child_node.child_0, base_temp);
            var idx_temp = lowerExpr(self, child_node.child_1);
            var rt_aoi = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
            var aoi_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
            if (rt_aoi) |t| { if (t != type_mod.TYPE_UNDEFINED) { aoi_box[0] = t; } }
            var tid = nextTemp(self, aoi_box[0]);
            emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = base_temp, .rhs = idx_temp, .result = tid } });
            return tid;
        }
        var operand_temp = lowerExpr(self, node.child_0);
        var rt_ao = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ao_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
        if (rt_ao) |t| { if (t != type_mod.TYPE_UNDEFINED) { ao_box[0] = t; } }
        var tid = nextTemp(self, ao_box[0]);
        emitInst(self, LirInst{ .addr_of = .{ .operand = operand_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.index_access) {
        var base_temp = lowerExpr(self, node.child_0);
        base_temp = maybeExtractSlicePtr(self, node.child_0, base_temp);
        var idx_temp = lowerExpr(self, node.child_1);
        var elem_type: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var rt_ix = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (rt_ix) |t| { if (t != type_mod.TYPE_UNDEFINED) { elem_type[0] = t; } }
        else {
        var reg = self.ctx.registry;
        var bt = self.hoisted_temps.items[@intCast(usize, base_temp)].type_id;
        if (bt != type_mod.TYPE_UNDEFINED) {
            var bty = reg.types_items[@intCast(usize, bt)];
            if (bty.kind == type_mod.TypeKind.slice_type) {
                elem_type[0] = reg.slice_items[@intCast(usize, bty.payload_idx)].elem;
            } else if (bty.kind == type_mod.TypeKind.array_type) {
                elem_type[0] = reg.array_items[@intCast(usize, bty.payload_idx)].elem;
            }
        }
        }
        var tid = nextTemp(self, elem_type[0]);
        emitInst(self, LirInst{ .load_index = .{ .base = base_temp, .index = idx_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.ident_expr) {
        var name_id = store.identifiers.items[@intCast(usize, node.payload)];
        if (self.ctx.has_symbols != @intCast(u8, 0)) {
         var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, name_id);
         if (sym) |s| {
               if (s.kind == sym_mod.SymbolKind.global) {
                   if ((@intCast(u16, s.flags) & @intCast(u16, 1)) == @intCast(u16, 0)) {
                      var decl_node = store.nodes.items[@intCast(usize, s.decl_node)];
                      if (decl_node.child_1 != 0) {
                          var init_node = store.nodes.items[@intCast(usize, decl_node.child_1)];
                          if (init_node.kind == AstKind.int_literal) {
                             var val = store.int_values.items[@intCast(usize, init_node.payload)];
                             var tid = nextTemp(self, type_mod.TYPE_U32);
                             emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
                             return tid;
                         }
                         if (init_node.kind == AstKind.float_literal) {
                             var val = store.float_values.items[@intCast(usize, init_node.payload)];
                             var tid = nextTemp(self, type_mod.TYPE_F64);
                             emitInst(self, LirInst{ .float_const = .{ .value = val, .result = tid } });
                             return tid;
                         }
                         if (init_node.kind == AstKind.char_literal) {
                             var val = store.int_values.items[@intCast(usize, init_node.payload)];
                             var tid = nextTemp(self, type_mod.TYPE_U8);
                             emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
                             return tid;
                         }
                     }
                    }
                      var gdb_here: []const u8 = "GDB_HERE_SYM"; pal.stderr_write(gdb_here);
                      var gtdb: [20]u8 = undefined; var gtdl = itoa_mod.itoa(s.type_id, gtdb[0..]); var gtds: usize = @intCast(usize, 19) - @intCast(usize, gtdl); pal.stderr_write(gtdb[gtds..@intCast(usize, 19)]);
                      var gkk: u32 = s.kind;
                      var gkdb: [20]u8 = undefined; var gkdl = itoa_mod.itoa(gkk, gkdb[0..]); var gkds: usize = @intCast(usize, 19) - @intCast(usize, gkdl); pal.stderr_write(gkdb[gkds..@intCast(usize, 19)]);
                      var gdn: []const u8 = "d"; pal.stderr_write(gdn);
                      var gddb: [20]u8 = undefined; var gddl = itoa_mod.itoa(s.decl_node, gddb[0..]); var gdds: usize = @intCast(usize, 19) - @intCast(usize, gddl); pal.stderr_write(gddb[gdds..@intCast(usize, 19)]);
                      var gnn: []const u8 = "n"; pal.stderr_write(gnn);
                      var gndb: [20]u8 = undefined; var gndl = itoa_mod.itoa(s.name_id, gndb[0..]); var gnds: usize = @intCast(usize, 19) - @intCast(usize, gndl); pal.stderr_write(gndb[gnds..@intCast(usize, 19)]);
                      var gnl2: []const u8 = "\n"; pal.stderr_write(gnl2);
                      var skip_rt: u32 = s.type_id;
                      if (skip_rt != @intCast(u32, 0)) {
                         var srty = self.ctx.registry.types_items[@intCast(usize, skip_rt)];
                         if (srty.kind == type_mod.TypeKind.fn_type or srty.kind == type_mod.TypeKind.module_type) {
                             return type_mod.TYPE_UNDEFINED;
                         }
                     }
                     if (s.decl_node != 0) {
                         var dn_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, s.decl_node);
                         var b2m: []const u8 = "B2:dn"; pal.stderr_write(b2m);
                         var b2db: [20]u8 = undefined; var b2dl = itoa_mod.itoa(s.decl_node, b2db[0..]); var b2ds: usize = @intCast(usize, 19) - @intCast(usize, b2dl); pal.stderr_write(b2db[b2ds..@intCast(usize, 19)]);
                         if (dn_type) |dt| {
                             var b2hm: []const u8 = "H"; pal.stderr_write(b2hm);
                             var dty = self.ctx.registry.types_items[@intCast(usize, dt)];
                             var b2kb: [20]u8 = undefined; var b2kl = itoa_mod.itoa(@intCast(u32, @enumToInt(dty.kind)), b2kb[0..]); var b2ks: usize = @intCast(usize, 19) - @intCast(usize, b2kl); pal.stderr_write(b2kb[b2ks..@intCast(usize, 19)]);
                             if (dty.kind == type_mod.TypeKind.fn_type or dty.kind == type_mod.TypeKind.module_type) {
                                 return @intCast(u32, 0);
                             }
                         } else {
                             var b2mm: []const u8 = "M"; pal.stderr_write(b2mm);
                         }
                         var b2nl: []const u8 = "\n"; pal.stderr_write(b2nl);
                     }
                     return lowerGlobalRef(self, s.*, name_id);
                } else if (s.kind == sym_mod.SymbolKind.module) {
                    var m1m: []const u8 = "M1:"; pal.stderr_write(m1m);
                    return type_mod.TYPE_UNDEFINED;
                }
         }
        }
        var ptype: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        var arr_temp: u32 = findLocalTemp(self, name_id);
        var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (rt) |t| {
            if (t != type_mod.TYPE_UNDEFINED) {
                var rty = self.ctx.registry.types_items[@intCast(usize, t)];
                if (rty.kind == type_mod.TypeKind.fn_type or rty.kind == type_mod.TypeKind.module_type) {
                    return @intCast(u32, 0);
                }
                ptype = t;
            }
        }
        if (ptype == type_mod.TYPE_UNDEFINED) {
            var fu: []const u8 = "F3cU:n"; pal.stderr_write(fu);
            var fub: [20]u8 = undefined; var ful = itoa_mod.itoa(name_id, fub[0..]); var fus: usize = @intCast(usize, 19) - @intCast(usize, ful); pal.stderr_write(fub[fus..@intCast(usize, 19)]);
            var fus2: []const u8 = "s"; pal.stderr_write(fus2);
            var fsn = si_mod.stringInternerGet(self.ctx.registry.interner, name_id);
            pal.stderr_write(fsn);
            var funl2: []const u8 = " "; pal.stderr_write(funl2);
            ptype = type_mod.TYPE_U32;
        }
        if (arr_temp != @intCast(u32, 0)) { return arr_temp; }
        var tid = nextTemp(self, ptype);
        emitInst(self, LirInst{ .load_local = .{ .name_id = name_id, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.field_access) {
        var field_name_id = node.payload;
        var base_node = store.nodes.items[@intCast(usize, node.child_0)];
        if (base_node.kind == AstKind.ident_expr and self.ctx.has_symbols != @intCast(u8, 0)) {
            var base_name_id = store.identifiers.items[@intCast(usize, base_node.payload)];
            var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, base_name_id);
            if (sym) |s| {
                if (s.kind == sym_mod.SymbolKind.type_alias) {
                    var key: u64 = @intCast(u64, self.module_id) * @intCast(u64, 4294967296) + @intCast(u64, base_name_id);
                    var lt = type_mod.nameCacheGet(self.ctx.registry, key);
                    if (lt) |type_id| {
                        var f3s: []const u8 = "F3:1\n"; pal.stderr_write(f3s);
                        var ty = self.ctx.registry.types_items[@intCast(usize, type_id)];
                        if (ty.kind == type_mod.TypeKind.tagged_union_type) {
                            var tp = self.ctx.registry.tu_items[@intCast(usize, ty.payload_idx)];
                            var fstart: usize = @intCast(usize, tp.fields_start);
                            var fcount: usize = @intCast(usize, tp.fields_count);
                            var fi: usize = 0;
                            while (fi < fcount) : (fi += 1) {
                                if (self.ctx.registry.fe_items[fstart + fi].name_id == field_name_id) {
                                    var tid = nextTemp(self, tp.tag_type);
                                    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, fi), .result = tid } });
                                    return tid;
                                }
                            }
                        }
                    }
                }
            }
        }
        var base_temp = lowerExpr(self, node.child_0);
        var resolved_base = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (resolved_base) |_| { var f4s: []const u8 = "F4:H\n"; pal.stderr_write(f4s); } else { var f4s: []const u8 = "F4:M\n"; pal.stderr_write(f4s); }
        var rt_fa = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var fa_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_fa) |t| { if (t != type_mod.TYPE_UNDEFINED) { fa_box[0] = t; } }
        var d1f: []const u8 = "D1:FADr"; pal.stderr_write(d1f);
        var d1fb: [20]u8 = undefined;
        if (rt_fa) |d1t| { var d1fl = itoa_mod.itoa(d1t, d1fb[0..]); var d1fs: usize = @intCast(usize, 19) - @intCast(usize, d1fl); pal.stderr_write(d1fb[d1fs..@intCast(usize, 19)]); }
        else { var d1z: []const u8 = "NULL"; pal.stderr_write(d1z); }
        var d1fn: []const u8 = "fn"; pal.stderr_write(d1fn);
        var d1fnb: [20]u8 = undefined; var d1fnl = itoa_mod.itoa(field_name_id, d1fnb[0..]); var d1fns: usize = @intCast(usize, 19) - @intCast(usize, d1fnl); pal.stderr_write(d1fnb[d1fns..@intCast(usize, 19)]);
        var d1nl: []const u8 = " "; pal.stderr_write(d1nl);
        var fa_ty = self.ctx.registry.types_items[@intCast(usize, fa_box[0])];
        if (fa_ty.kind == type_mod.TypeKind.fn_type or fa_ty.kind == type_mod.TypeKind.module_type) {
            return @intCast(u32, 0);
        }
        var fas_m: []const u8 = "FAS:n"; pal.stderr_write(fas_m);
        var fas_b: [20]u8 = undefined; var fas_l = itoa_mod.itoa(field_name_id, fas_b[0..]); var fas_s: usize = @intCast(usize, 19) - @intCast(usize, fas_l); pal.stderr_write(fas_b[fas_s..@intCast(usize, 19)]);
        var fas_tn: []const u8 = "t"; pal.stderr_write(fas_tn);
        var fas_tb: [20]u8 = undefined; var fas_tl = itoa_mod.itoa(fa_box[0], fas_tb[0..]); var fas_ts: usize = @intCast(usize, 19) - @intCast(usize, fas_tl); pal.stderr_write(fas_tb[fas_ts..@intCast(usize, 19)]);
        var fas_nl: []const u8 = " "; pal.stderr_write(fas_nl);
        var tid = nextTemp(self, fa_box[0]);
        if (resolved_base) |type_id| {
            var ty = self.ctx.registry.types_items[@intCast(usize, type_id)];
            var kind = ty.kind;
            if (kind == type_mod.TypeKind.slice_type) {
                var elem = self.ctx.registry.slice_items[@intCast(usize, ty.payload_idx)].elem;
                var len_s: []const u8 = "len";
                var len_id = si_mod.stringInternerIntern(self.ctx.registry.interner, len_s);
                if (field_name_id == len_id) {
                    var f4sl: []const u8 = "F4SL\n"; pal.stderr_write(f4sl);
                    tid = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .load_field = .{ .base = base_temp, .field_id = @intCast(u32, 1), .result = tid } });
                } else {
                    var pty = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, elem, false);
                    tid = nextTemp(self, pty);
                    emitInst(self, LirInst{ .load_field = .{ .base = base_temp, .field_id = @intCast(u32, 0), .result = tid } });
                }
                return tid;
            } else if (kind == type_mod.TypeKind.struct_type or kind == type_mod.TypeKind.union_type or kind == type_mod.TypeKind.tagged_union_type) {
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
        var d9m: []const u8 = "D9:FCk"; pal.stderr_write(d9m);
        var callee_head = store.nodes.items[@intCast(usize, node.child_0)];
        var ck_val: u8 = callee_head.kind;
        var d9kb: [10]u8 = undefined; var d9kl = itoa_mod.itoa(@intCast(u32, ck_val), d9kb[0..]); var d9ks: usize = @intCast(usize, 9) - @intCast(usize, d9kl); pal.stderr_write(d9kb[d9ks..@intCast(usize, 9)]);
        var d9sp: []const u8 = " "; pal.stderr_write(d9sp);
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        if (ec.len >= @intCast(usize, 2)) {
            var first = store.nodes.items[@intCast(usize, ec[0])];
            var second = store.nodes.items[@intCast(usize, ec[1])];
            if (first.kind == AstKind.string_literal and second.kind == AstKind.tuple_literal) {
                var d2m: []const u8 = "D2:PRINTx"; pal.stderr_write(d2m);
                var fk_val: u8 = first.kind; var sk_val: u8 = second.kind;
                var d2xb: [10]u8 = undefined; var d2xl = itoa_mod.itoa(@intCast(u32, fk_val), d2xb[0..]); var d2xs: usize = @intCast(usize, 9) - @intCast(usize, d2xl); pal.stderr_write(d2xb[d2xs..@intCast(usize, 9)]);
                var d2ym: []const u8 = "y"; pal.stderr_write(d2ym);
                var d2yb: [10]u8 = undefined; var d2yl = itoa_mod.itoa(@intCast(u32, sk_val), d2yb[0..]); var d2ys: usize = @intCast(usize, 9) - @intCast(usize, d2yl); pal.stderr_write(d2yb[d2ys..@intCast(usize, 9)]);
                var d2am: []const u8 = "a"; pal.stderr_write(d2am);
                var d2ab: [10]u8 = undefined; var d2al = itoa_mod.itoa(@intCast(u32, ec.len), d2ab[0..]); var d2as: usize = @intCast(usize, 9) - @intCast(usize, d2al); pal.stderr_write(d2ab[d2as..@intCast(usize, 9)]);
                var d2nl: []const u8 = "\n"; pal.stderr_write(d2nl);
                return lowerPrintCall(self, ec);
            } else {
                var d2b: []const u8 = "D2b:x"; pal.stderr_write(d2b);
                var fkv: u8 = first.kind; var d2xb2: [10]u8 = undefined; var d2xl2 = itoa_mod.itoa(@intCast(u32, fkv), d2xb2[0..]); var d2xs2: usize = @intCast(usize, 9) - @intCast(usize, d2xl2); pal.stderr_write(d2xb2[d2xs2..@intCast(usize, 9)]);
                var d2by: []const u8 = "y"; pal.stderr_write(d2by);
                var skv: u8 = second.kind; var d2yb2: [10]u8 = undefined; var d2yl2 = itoa_mod.itoa(@intCast(u32, skv), d2yb2[0..]); var d2ys2: usize = @intCast(usize, 9) - @intCast(usize, d2yl2); pal.stderr_write(d2yb2[d2ys2..@intCast(usize, 9)]);
                var d2blen: []const u8 = "L"; pal.stderr_write(d2blen);
                var d2blenb: [10]u8 = undefined; var d2blenl = itoa_mod.itoa(@intCast(u32, ec.len), d2blenb[0..]); var d2blens: usize = @intCast(usize, 9) - @intCast(usize, d2blenl); pal.stderr_write(d2blenb[d2blens..@intCast(usize, 9)]);
                if (ec.len >= @intCast(usize, 3)) {
                    var third = store.nodes.items[@intCast(usize, ec[2])];
                    var d2bz: []const u8 = "z"; pal.stderr_write(d2bz);
                    var tzv: u8 = third.kind; var d2zxb2: [10]u8 = undefined; var d2zxl2 = itoa_mod.itoa(@intCast(u32, tzv), d2zxb2[0..]); var d2zxs2: usize = @intCast(usize, 9) - @intCast(usize, d2zxl2); pal.stderr_write(d2zxb2[d2zxs2..@intCast(usize, 9)]);
                }
                var d2bnl: []const u8 = "\n"; pal.stderr_write(d2bnl);
            }
        }
        var callee_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (callee_rt) |crt| {
            var crt_ty = self.ctx.registry.types_items[@intCast(usize, crt)];
            if (crt_ty.kind == type_mod.TypeKind.fn_type) {
                var fp = self.ctx.registry.fn_items[@intCast(usize, crt_ty.payload_idx)];
                var args_start = self.temp_counter;
                var ai: usize = 0;
                while (ai < ec.len) : (ai += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                ai = 0;
                while (ai < ec.len) : (ai += 1) {
                    var arg_val = lowerExpr(self, ec[ai]);
                    emitInst(self, LirInst{ .assign = .{ .dst = args_start + @intCast(u32, ai), .src = arg_val } });
                    var sbox: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                    if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| { sbox[0] = pt; }
                    else { sbox[0] = self.hoisted_temps.items[@intCast(usize, arg_val)].type_id; }
                    self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = sbox[0];
                }
                var result: u32 = @intCast(u32, 0);
                if (fp.return_type != type_mod.TYPE_VOID and fp.return_type != type_mod.TYPE_UNDEFINED) {
                    result = nextTemp(self, fp.return_type);
                }
                var rt1: []const u8 = "RT1"; pal.stderr_write(rt1);
                emitInst(self, LirInst{ .call_direct = .{
                    .name_id = fp.name_id,
                    .module_id = self.module_id,
                    .args_start = args_start,
                    .args_count = @intCast(u32, ec.len),
                    .result = result,
                    .return_type = fp.return_type,
                } });
                return result;
            }
        }
        var callee_node = store.nodes.items[@intCast(usize, node.child_0)];
        if (callee_node.kind == @enumToInt(AstKind.field_access)) {
            var dfa: []const u8 = "DFA:ck="; pal.stderr_write(dfa);
            var ckv: u8 = callee_node.kind; var dfab: [10]u8 = undefined; var dfal = itoa_mod.itoa(@intCast(u32, ckv), dfab[0..]); var dfas: usize = @intCast(usize, 9) - @intCast(usize, dfal); pal.stderr_write(dfab[dfas..@intCast(usize, 9)]);
            var dfasp: []const u8 = "\n"; pal.stderr_write(dfasp);
            var bnode = store.nodes.items[@intCast(usize, callee_node.child_0)];
            var bkv: u8 = bnode.kind; var bfb: [10]u8 = undefined; var bfl = itoa_mod.itoa(@intCast(u32, bkv), bfb[0..]); var bfs: usize = @intCast(usize, 9) - @intCast(usize, bfl); pal.stderr_write(bfb[bfs..@intCast(usize, 9)]); var bfsp: []const u8 = "bk\n"; pal.stderr_write(bfsp);
            var base_node = bnode;
            if (base_node.kind == AstKind.ident_expr or base_node.kind == @enumToInt(AstKind.field_access)) {
            var field_name_id: u32 = callee_node.payload;
            if (base_node.kind == @enumToInt(AstKind.field_access)) {
                    var chain: [4]u32 = undefined;
                    var chain_len: u32 = @intCast(u32, 0);
                    chain[@intCast(usize, chain_len)] = callee_node.payload; chain_len += @intCast(u32, 1);
                    var cw = base_node;
                    while (cw.kind == @enumToInt(AstKind.field_access)) {
                        chain[@intCast(usize, chain_len)] = cw.payload; chain_len += @intCast(u32, 1);
                        cw = store.nodes.items[@intCast(usize, cw.child_0)];
                    }
                    if (cw.kind != @enumToInt(AstKind.ident_expr)) { return @intCast(u32, 0); }
                    base_node = cw;
                    field_name_id = chain[@intCast(usize, 0)];
                    var cmod: u32 = self.module_id;
                    var ci: u32 = chain_len;
                    while (ci > @intCast(u32, 1)) {
                        ci -= @intCast(u32, 1);
                        var cf = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, cmod, chain[@intCast(usize, ci)]);
                        if (cf) |cfs| {
                            if (cfs.module_id != @intCast(u32, 0)) { cmod = cfs.module_id; }
                            else { return @intCast(u32, 0); }
                        } else { return @intCast(u32, 0); }
                    }
                    var chain_ok: []const u8 = "CHAIN:r\n"; pal.stderr_write(chain_ok);
                }
                var base_name_id = store.identifiers.items[@intCast(usize, base_node.payload)];
                var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, base_name_id);
                if (sym) |sm| {
                    var d5m: []const u8 = "D5:sm="; pal.stderr_write(d5m);
                    var d5mb: [10]u8 = undefined; var d5ml = itoa_mod.itoa(sm.module_id, d5mb[0..]); var d5ms: usize = @intCast(usize, 9) - @intCast(usize, d5ml); pal.stderr_write(d5mb[d5ms..@intCast(usize, 9)]);
                    var d5bn: []const u8 = "bn"; pal.stderr_write(d5bn);
                    var d5bnb: [10]u8 = undefined; var d5bnl = itoa_mod.itoa(base_name_id, d5bnb[0..]); var d5bns: usize = @intCast(usize, 9) - @intCast(usize, d5bnl); pal.stderr_write(d5bnb[d5bns..@intCast(usize, 9)]);
                    var d5nl: []const u8 = " "; pal.stderr_write(d5nl);
                    if (sm.module_id != @intCast(u32, 0) and sm.module_id != self.module_id) {
                        var dz1_m: []const u8 = "DZ1:PASS\n"; pal.stderr_write(dz1_m);
                        var target_mod_id = sm.module_id;
                        var field_name_id = callee_node.payload;
                        var field_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, target_mod_id, field_name_id);
                        if (field_sym) |fs| { var a3: []const u8 = "F3a1"; pal.stderr_write(a3);
                            if (fs.kind == @intCast(u8, 3)) {
                                 var call_ns: u32 = self.temp_counter;
                                 var ai: usize = 0;
                                 while (ai < ec.len) : (ai += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                                 ai = 0;
                                 while (ai < ec.len) : (ai += 1) {
                                      var call_val = lowerExpr(self, ec[ai]);
                                      emitInst(self, LirInst{ .assign = .{ .dst = call_ns + @intCast(u32, ai), .src = call_val } });
                                      var slot_tid_a: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                                      if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| { slot_tid_a[0] = pt; var hx: []const u8 = "H"; pal.stderr_write(hx); }
                                      else { slot_tid_a[0] = self.hoisted_temps.items[@intCast(usize, call_val)].type_id; var mx: []const u8 = "M"; pal.stderr_write(mx); }
                                      self.hoisted_temps.items[@intCast(usize, call_ns) + ai].type_id = slot_tid_a[0];
                                 }
                                 var args_count: u32 = @intCast(u32, ec.len);
                                 self._fn_ret_type = type_mod.TYPE_UNDEFINED;
                                 if (fs.decl_node != 0) {
                                     var dn = store.nodes.items[@intCast(usize, fs.decl_node)];
                                     if (dn.kind == @enumToInt(AstKind.fn_decl)) {
                                         var proto = store.fn_protos.items[@intCast(usize, dn.payload)];
                                         if (proto.return_type_node != 0) {
                                             var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, proto.return_type_node);
                                             if (rt) |_| { var dx: []const u8 = "HX"; pal.stderr_write(dx); } else { var dx: []const u8 = "MX"; pal.stderr_write(dx); }
                                              if (rt) |t| { self._fn_ret_type = t; }
                                         }
                                     }
                                 }
                                 var result: u32 = @intCast(u32, 0);
                                 if (self._fn_ret_type != type_mod.TYPE_VOID and self._fn_ret_type != type_mod.TYPE_UNDEFINED) {
                                     var c3m: []const u8 = "C3:"; pal.stderr_write(c3m);
                                     var c3b: [20]u8 = undefined; var c3l = itoa_mod.itoa(self._fn_ret_type, c3b[0..]); var c3s: usize = @intCast(usize, 19) - @intCast(usize, c3l); pal.stderr_write(c3b[c3s..@intCast(usize, 19)]);
                                     var c3nl: []const u8 = "\n"; pal.stderr_write(c3nl);
                                     result = nextTemp(self, self._fn_ret_type);
                                 }
                                    var ad3m: []const u8 = "ADX:n"; pal.stderr_write(ad3m);
                                    var adx1b: [10]u8 = undefined; var adx1l = itoa_mod.itoa(fs.name_id, adx1b[0..]); var adx1s: usize = @intCast(usize, 9) - @intCast(usize, adx1l); pal.stderr_write(adx1b[adx1s..@intCast(usize, 9)]);
                                    var adx1m: []const u8 = "m"; pal.stderr_write(adx1m);
                                    var adx1mb: [10]u8 = undefined; var adx1ml = itoa_mod.itoa(target_mod_id, adx1mb[0..]); var adx1ms: usize = @intCast(usize, 9) - @intCast(usize, adx1ml); pal.stderr_write(adx1mb[adx1ms..@intCast(usize, 9)]);
                                    var adx1nl: []const u8 = "\n"; pal.stderr_write(adx1nl);
                                    emitInst(self, LirInst{ .call_direct = .{
                                        .name_id = fs.name_id,
                                        .module_id = target_mod_id,
                                        .args_start = call_ns,
                                        .args_count = args_count,
                                        .result = result,
                                        .return_type = self._fn_ret_type,
                                    } });
                                return result;
                            } else { var fk_val: u8 = fs.kind; var a3f: []const u8 = "F3aKk"; pal.stderr_write(a3f); var a3fkb: [10]u8 = undefined; var a3fkl = itoa_mod.itoa(@intCast(u32, fk_val), a3fkb[0..]); var a3fks: usize = @intCast(usize, 9) - @intCast(usize, a3fkl); pal.stderr_write(a3fkb[a3fks..@intCast(usize, 9)]); var a3fsp: []const u8 = "\n"; pal.stderr_write(a3fsp); }
                        } else { var a3m: []const u8 = "DZ1:NF"; pal.stderr_write(a3m); var a3mb: [10]u8 = undefined; var a3ml = itoa_mod.itoa(field_name_id, a3mb[0..]); var a3ms: usize = @intCast(usize, 9) - @intCast(usize, a3ml); pal.stderr_write(a3mb[a3ms..@intCast(usize, 9)]); var a3mns: []const u8 = " "; pal.stderr_write(a3mns); }
                    } else { var dz1_fail: []const u8 = "DZ1:MSKIP\n"; pal.stderr_write(dz1_fail); }
                } else { var a3b: []const u8 = "F3aBn"; pal.stderr_write(a3b); var a3bb: [10]u8 = undefined; var a3bl = itoa_mod.itoa(base_name_id, a3bb[0..]); var a3bs: usize = @intCast(usize, 9) - @intCast(usize, a3bl); pal.stderr_write(a3bb[a3bs..@intCast(usize, 9)]); var a3bns: []const u8 = " "; pal.stderr_write(a3bns); }
            }
        } else if (callee_node.kind == @enumToInt(AstKind.ident_expr)) {
            var callee_name_id = store.identifiers.items[@intCast(usize, callee_node.payload)];
            var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, callee_name_id);
            if (sym) |sm| { var sf: []const u8 = "S"; pal.stderr_write(sf);
                if (sm.kind == @intCast(u8, 0)) { var d3m: []const u8 = "D3:SKIPn"; pal.stderr_write(d3m); var d3nb: [10]u8 = undefined; var d3nl = itoa_mod.itoa(callee_name_id, d3nb[0..]); var d3ns: usize = @intCast(usize, 9) - @intCast(usize, d3nl); pal.stderr_write(d3nb[d3ns..@intCast(usize, 9)]); var d3kn: []const u8 = "k0"; pal.stderr_write(d3kn); }
                else if (sm.kind == @intCast(u8, 1)) { var d3m: []const u8 = "D3:SKIPn"; pal.stderr_write(d3m); var d3nb: [10]u8 = undefined; var d3nl = itoa_mod.itoa(callee_name_id, d3nb[0..]); var d3ns: usize = @intCast(usize, 9) - @intCast(usize, d3nl); pal.stderr_write(d3nb[d3ns..@intCast(usize, 9)]); var d3kn: []const u8 = "k1"; pal.stderr_write(d3kn); }
                else if (sm.kind == @intCast(u8, 2) or sm.kind == @intCast(u8, 3)) { var d3m: []const u8 = "D3:OKn"; pal.stderr_write(d3m); var d3nb: [10]u8 = undefined; var d3nl = itoa_mod.itoa(callee_name_id, d3nb[0..]); var d3ns: usize = @intCast(usize, 9) - @intCast(usize, d3nl); pal.stderr_write(d3nb[d3ns..@intCast(usize, 9)]); var d3kn: []const u8 = "k"; pal.stderr_write(d3kn); var d3kb: [10]u8 = undefined; var d3kl = itoa_mod.itoa(sm.kind, d3kb[0..]); var d3ks: usize = @intCast(usize, 9) - @intCast(usize, d3kl); pal.stderr_write(d3kb[d3ks..@intCast(usize, 9)]);
                    var args_start = self.temp_counter;
                    var ai: usize = 0;
                    while (ai < ec.len) : (ai += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                    ai = 0;
                    while (ai < ec.len) : (ai += 1) {
                        var arg_val = lowerExpr(self, ec[ai]);
                        emitInst(self, LirInst{ .assign = .{ .dst = args_start + @intCast(u32, ai), .src = arg_val } });
                        var slot_tid_b: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                        if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| { slot_tid_b[0] = pt; var hx2: u32 = 1; if (hx2 == 1) { var px: usize = 999999; hx2 = 0; } }
                        else { slot_tid_b[0] = self.hoisted_temps.items[@intCast(usize, arg_val)].type_id; var mx2: u32 = 2; if (mx2 == 2) { var qx: usize = 999998; mx2 = 0; } }
                        self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = slot_tid_b[0];
                    }
                    var args_count: u32 = @intCast(u32, ec.len);
                    self._fn_ret_type = type_mod.TYPE_UNDEFINED;
                    if (sm.decl_node != 0) {
                        var dn = store.nodes.items[@intCast(usize, sm.decl_node)];
                        if (dn.kind == @intCast(u8, 2)) {
                            var proto = store.fn_protos.items[@intCast(usize, dn.payload)];
                            if (proto.return_type_node != 0) {
                                var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, proto.return_type_node);
                                if (rt) |_| { var dd: []const u8 = "HD"; pal.stderr_write(dd); } else { var dd: []const u8 = "MD"; pal.stderr_write(dd); }
                                if (rt) |t| { self._fn_ret_type = t; }
                            }
                        }
                    }
                    var result: u32 = @intCast(u32, 0);
                    if (self._fn_ret_type != type_mod.TYPE_VOID and self._fn_ret_type != type_mod.TYPE_UNDEFINED) {
                        var c3m2: []const u8 = "C3:"; pal.stderr_write(c3m2);
                        var c3b2: [20]u8 = undefined; var c3l2 = itoa_mod.itoa(self._fn_ret_type, c3b2[0..]); var c3s2: usize = @intCast(usize, 19) - @intCast(usize, c3l2); pal.stderr_write(c3b2[c3s2..@intCast(usize, 19)]);
                        var c3nl2: []const u8 = "\n"; pal.stderr_write(c3nl2);
                        result = nextTemp(self, self._fn_ret_type);
                    }
                    var ad3m2: []const u8 = "ADX:n"; pal.stderr_write(ad3m2);
                    var adx2b: [10]u8 = undefined; var adx2l = itoa_mod.itoa(sm.name_id, adx2b[0..]); var adx2s: usize = @intCast(usize, 9) - @intCast(usize, adx2l); pal.stderr_write(adx2b[adx2s..@intCast(usize, 9)]);
                    var adx2m: []const u8 = "m"; pal.stderr_write(adx2m);
                    var adx2mb: [10]u8 = undefined; var adx2ml = itoa_mod.itoa(sm.module_id, adx2mb[0..]); var adx2ms: usize = @intCast(usize, 9) - @intCast(usize, adx2ml); pal.stderr_write(adx2mb[adx2ms..@intCast(usize, 9)]);
                    var adx2nl: []const u8 = "\n"; pal.stderr_write(adx2nl);
                    emitInst(self, LirInst{ .call_direct = .{
                        .name_id = sm.name_id,
                        .module_id = sm.module_id,
                        .args_start = args_start,
                        .args_count = args_count,
                        .result = result,
                        .return_type = self._fn_ret_type,
                    } });
                    return result;
                }
            }
        }
        var a3p: []const u8 = "F3aP"; pal.stderr_write(a3p);
        var callee_cn = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        var a3pt: [20]u8 = undefined; var a3ptl = itoa_mod.itoa(callee_cn.kind, a3pt[0..]); var a3pts: usize = @intCast(usize, 19) - @intCast(usize, a3ptl); pal.stderr_write(a3pt[a3pts..@intCast(usize, 19)]);
        if (callee_cn.kind == AstKind.ident_expr) {
            var a3pn: []const u8 = "n"; pal.stderr_write(a3pn);
            var a3pnb: [20]u8 = undefined; var a3pnl = itoa_mod.itoa(self.ctx.store.identifiers.items[@intCast(usize, callee_cn.payload)], a3pnb[0..]); var a3pns: usize = @intCast(usize, 19) - @intCast(usize, a3pnl); pal.stderr_write(a3pnb[a3pns..@intCast(usize, 19)]);
        }
        var a3pnl: []const u8 = " "; pal.stderr_write(a3pnl);
        var callee_temp = lowerExpr(self, node.child_0);
        var args_start = self.temp_counter;
        var ai2: usize = 0;
        while (ai2 < ec.len) : (ai2 += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
        ai2 = 0;
        while (ai2 < ec.len) : (ai2 += 1) {
            var arg_val = lowerExpr(self, ec[ai2]);
            emitInst(self, LirInst{ .assign = .{ .dst = args_start + @intCast(u32, ai2), .src = arg_val } });
        }
        var d2s3: []const u8 = "D2I:ns="; pal.stderr_write(d2s3);
        dbgPrintU32(args_start); var d2n3: []const u8 = " nc="; pal.stderr_write(d2n3);
        dbgPrintU32(@intCast(u32, ec.len)); var d2nl3: []const u8 = "\n"; pal.stderr_write(d2nl3);
         var result = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .call = .{
            .callee = callee_temp,
            .args_start = args_start,
            .args_count = @intCast(u32, ec.len),
            .result = result,
        } });
        return result;
    } else if (node.kind == AstKind.builtin_call) {
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var elm: []const u8 = "B"; pal.stderr_write(elm);
        if (node.child_0 == self.intcast_name_id) { var bm: []const u8 = "I"; pal.stderr_write(bm); }
        else { var bm: []const u8 = "F"; pal.stderr_write(bm); }
        var val_temp = lowerExpr(self, ec[@intCast(usize, 1)]);
        var ty_node = store.nodes.items[@intCast(usize, ec[@intCast(usize, 0)])];
        t_target = type_mod.TYPE_U32;
        if (ty_node.kind == AstKind.ident_expr) {
            var tn_id = store.identifiers.items[@intCast(usize, ty_node.payload)];
            var tn = type_mod.nameCacheGet(self.ctx.registry, @intCast(u64, tn_id));
            if (tn) |t| { t_target = t; var tt: []const u8 = "T"; pal.stderr_write(tt); }
            else { var tt: []const u8 = "t"; pal.stderr_write(tt); }
        } else { var tu: []const u8 = "U"; pal.stderr_write(tu); }
        var result = nextTemp(self, t_target);
        if (node.child_0 == self.intcast_name_id) {
            emitInst(self, LirInst{ .int_cast = .{
                .value = val_temp, .target = t_target, .result = result,
                .is_checked = @intCast(u8, 1),
            } });
        } else if (node.child_0 == self.inttofloat_name_id) {
            emitInst(self, LirInst{ .int_to_float = .{
                .value = val_temp, .target = t_target, .result = result,
            } });
        }
        return result;
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
        self.block_terminated = @intCast(u8, 1);
        self.current_bb = ok_bb;
        var result = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = inner_temp, .result = result } });
        if (self.block_terminated == @intCast(u8, 0)) {
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
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = ok_bb;
        var ok_val = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = lhs_temp, .result = ok_val } });
        emitInst(self, LirInst{ .assign = .{ .dst = join_temp, .src = ok_val } });
        if (self.block_terminated == @intCast(u8, 0)) {
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
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = ok_bb;
        var ok_val = nextTemp(self, type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_optional = .{ .value = lhs_temp, .result = ok_val } });
        emitInst(self, LirInst{ .assign = .{ .dst = join_temp, .src = ok_val } });
        if (self.block_terminated == @intCast(u8, 0)) {
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
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = else_bb;
        var else_val = lowerExpr(self, node.child_2);
        emitInst(self, LirInst{ .assign = .{ .dst = result, .src = else_val } });
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        return result;
     } else if (node.kind == AstKind.array_init) {
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var aelem: u32 = if (ec.len > @intCast(usize, 0)) if (store.nodes.items[@intCast(usize, ec[@intCast(usize, 0)])].kind == AstKind.char_literal) type_mod.TYPE_U8 else type_mod.TYPE_U32 else type_mod.TYPE_U32;
        var arr_tid = type_mod.typeRegistryGetOrCreateArray(self.ctx.registry, aelem, @intCast(u32, ec.len));
        var base_temp = nextTemp(self, arr_tid);
        var ei: usize = @intCast(usize, 0);
        while (ei < ec.len) : (ei += @intCast(usize, 1)) {
            var val_temp = lowerExpr(self, ec[ei]);
            var ix_temp = nextTemp(self, type_mod.TYPE_U32);
            emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, ei), .result = ix_temp } });
            emitInst(self, LirInst{ .assign_index = .{ .base = base_temp, .index = ix_temp, .src = val_temp } });
        }
        return base_temp;
    } else if (node.kind == AstKind.struct_init) {
        var init_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var base_temp = nextTemp(self, if (init_type) |it| it else type_mod.TYPE_UNDEFINED);
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var ei: usize = @intCast(usize, 0);
        while (ei < ec.len) : (ei += @intCast(usize, 1)) {
            var fi_node = store.nodes.items[@intCast(usize, ec[ei])];
            var fi_name_id = store.identifiers.items[@intCast(usize, fi_node.payload)];
            var val_temp = if (fi_node.child_1 != @intCast(u32, 0)) lowerExpr(self, fi_node.child_1) else @intCast(u32, 0);
            if (init_type) |it| {
                var ts = self.ctx.registry.types_items[@intCast(usize, it)];
                if (ts.kind == type_mod.TypeKind.tagged_union_type) {
                    var tp = self.ctx.registry.tu_items[@intCast(usize, ts.payload_idx)];
                    var fs: usize = @intCast(usize, tp.fields_start);
                    var fc: usize = @intCast(usize, tp.fields_count);
                    var fj: usize = @intCast(usize, 0);
                    while (fj < fc) : (fj += @intCast(usize, 1)) {
                        if (self.ctx.registry.fe_items[fs + fj].name_id == fi_name_id) {
                            emitInst(self, LirInst{ .assign_field = .{ .base = base_temp, .field_id = @intCast(u32, fj), .src = val_temp } });
                            break;
                        }
                    }
                } else if (ts.kind == type_mod.TypeKind.struct_type) {
                    var sp = self.ctx.registry.st_items[@intCast(usize, ts.payload_idx)];
                    var fs: usize = @intCast(usize, sp.fields_start);
                    var fc: usize = @intCast(usize, sp.fields_count);
                    var fj: usize = @intCast(usize, 0);
                    while (fj < fc) : (fj += @intCast(usize, 1)) {
                        if (self.ctx.registry.fe_items[fs + fj].name_id == fi_name_id) {
                            emitInst(self, LirInst{ .assign_field = .{ .base = base_temp, .field_id = @intCast(u32, fj), .src = val_temp } });
                            break;
                        }
                    }
                }
            }
        }
        return base_temp;
    } else if (node.kind == AstKind.tuple_literal) {
        var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var tupm: []const u8 = "TUP\n"; pal.stderr_write(tupm);
        if (ec.len == 0) {
            return nextTemp(self, type_mod.TYPE_VOID);
        }
        return lowerExpr(self, ec[0]);
    } else if (node.kind == AstKind.switch_expr) {
        var cond_temp = lowerExpr(self, node.child_0);
        var cond_ty_id = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (cond_ty_id) |ct| {
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .load_field = .{ .base = cond_temp, .field_id = @intCast(u32, 0), .result = tag_temp } });
                cond_temp = tag_temp;
            }
        }
        var prong_ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
        var prong_count = prong_ec.len;
        var result_temp = nextTemp(self, type_mod.TYPE_UNDEFINED);
        var switch_bb = self.current_bb;
        var prong_start = @intCast(u32, self.func.blocks.len);
        var pi: usize = @intCast(usize, 0);
        while (pi < prong_count) : (pi += @intCast(usize, 1)) { _ = createBlock(self); }
        var else_bb = createBlock(self);
        var exit_bb = createBlock(self);
        var cases_start = @intCast(u32, self.func.switch_cases.len);
        pi = @intCast(usize, 0);
        while (pi < prong_count) : (pi += @intCast(usize, 1)) {
            var prong_node = store.nodes.items[@intCast(usize, prong_ec[pi])];
            if (prong_node.flags & @intCast(u8, 1) != @intCast(u8, 0)) { continue; }
            var prong_bb_id = prong_start + @intCast(u32, pi);
            var case_ec = ast_mod.astStoreGetExtraChildren(store, prong_node.payload);
            var ci: usize = @intCast(usize, 0);
            while (ci < case_ec.len) : (ci += @intCast(usize, 1)) {
                var case_node = store.nodes.items[@intCast(usize, case_ec[ci])];
                var case_val: u64 = @intCast(u64, 0);
                if (case_node.kind == AstKind.int_literal) {
                    case_val = store.int_values.items[@intCast(usize, case_node.payload)];
                } else if (case_node.kind == AstKind.enum_literal) {
                    var evc: []const u8 = "EC"; pal.stderr_write(evc);
                    var cval: u64 = @intCast(u64, case_node.payload);
                    var lk = @intCast(u32, case_ec[ci]);
                    var lkb = @intCast(u8, lk & @intCast(u32, 0xFF));
                    var lkb_buf: [20]u8 = undefined;
                    var lkb_len = itoa_mod.itoa(@intCast(u32, lkb), lkb_buf[0..]);
                    var lkb_s: usize = @intCast(usize, 19) - @intCast(usize, lkb_len);
                    pal.stderr_write(lkb_buf[lkb_s..@intCast(usize, 19)]);
                    var lks: []const u8 = " "; pal.stderr_write(lks);
                    var cev = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, lk);
                    if (cev) |v| { cval = @intCast(u64, v); }
                    if (cval != @intCast(u64, case_node.payload)) { var ef: []const u8 = "EF"; pal.stderr_write(ef); }
                    else { var ef: []const u8 = "Ef"; pal.stderr_write(ef); }
                    case_val = cval;
                } else { continue; }
                lir_mod.switchCaseArrayListAppend(&self.func.switch_cases,
                    lir_mod.SwitchCase{ .value = case_val, .target_bb = prong_bb_id });
            }
        }
        var sc_len = @intCast(u32, self.func.switch_cases.len);
        var cases_count: u32 = sc_len - cases_start;
        var else_target = else_bb;
        pi = @intCast(usize, 0);
        while (pi < prong_count) : (pi += @intCast(usize, 1)) {
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
            self.block_terminated = @intCast(u8, 1);
        }
        pi = @intCast(usize, 0);
        while (pi < prong_count) : (pi += @intCast(usize, 1)) {
            var prong_node = store.nodes.items[@intCast(usize, prong_ec[pi])];
            var prong_bb_id = prong_start + @intCast(u32, pi);
            self.current_bb = prong_bb_id;
            self.block_terminated = @intCast(u8, 0);
            var prong_val = lowerExpr(self, prong_node.child_0);
            if (self.block_terminated == @intCast(u8, 0)) {
                emitInst(self, LirInst{ .assign = .{ .dst = result_temp, .src = prong_val } });
                emitInst(self, LirInst{ .jump = exit_bb });
            }
        }
        self.current_bb = exit_bb;
        return result_temp;
    } else if (node.kind == AstKind.slice_expr) {
        var se_base = lowerExpr(self, node.child_0);
        var se_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (se_rt) |st| {
            var se_bt = self.hoisted_temps.items[@intCast(usize, se_base)].type_id;
            if (se_bt != type_mod.TYPE_UNDEFINED) {
                var se_bty = self.ctx.registry.types_items[@intCast(usize, se_bt)];
                if (se_bty.kind == type_mod.TypeKind.array_type) {
                    var se_arr_len = self.ctx.registry.array_items[@intCast(usize, se_bty.payload_idx)].length;
                    var se_len_temp = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, se_arr_len), .result = se_len_temp } });
                    var se_result = nextTemp(self, st);
                    emitInst(self, LirInst{ .make_slice = .{ .ptr = se_base, .len = se_len_temp, .result = se_result, .type_id = st } });
                    return se_result;
                }
            }
        }
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
            self.block_terminated = @intCast(u8, 0);
            lowerStmt(self, ec[i]);
        }
    } else {
        lowerStmt(self, node_idx);
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
        var if_c0: []const u8 = "IF:c0="; pal.stderr_write(if_c0);
        var if_c0b: [10]u8 = undefined; var if_c0l = itoa_mod.itoa(node.child_0, if_c0b[0..]); var if_c0s: usize = @intCast(usize, 9) - @intCast(usize, if_c0l); pal.stderr_write(if_c0b[if_c0s..@intCast(usize, 9)]);
        var if_kh: []const u8 = " k="; pal.stderr_write(if_kh);
        if (node.child_0 != @intCast(u32, 0)) {
            var cond_n = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
            var if_ckl = itoa_mod.itoa(cond_n.kind, if_c0b[0..]); var if_cks: usize = @intCast(usize, 9) - @intCast(usize, if_ckl); pal.stderr_write(if_c0b[if_cks..@intCast(usize, 9)]);
        } else {
            var if_z: []const u8 = "ZERO"; pal.stderr_write(if_z);
        }
        var if_nl: []const u8 = "\n"; pal.stderr_write(if_nl);
        var cond_temp = lowerExpr(self, node.child_0);
        var cond_ty_id = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (cond_ty_id) |ct| {
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var a3b: []const u8 = "F3bT"; pal.stderr_write(a3b);
                var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .load_field = .{ .base = cond_temp, .field_id = @intCast(u32, 0), .result = tag_temp } });
                cond_temp = tag_temp;
            }
        }
        if (@intCast(usize, cond_temp) < self.hoisted_temps.len) {
        var d10m: []const u8 = "D10:k"; pal.stderr_write(d10m);
        var cond_node_k = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        var d10kb: [20]u8 = undefined; var d10kl = itoa_mod.itoa(cond_node_k.kind, d10kb[0..]); var d10ks: usize = @intCast(usize, 19) - @intCast(usize, d10kl); pal.stderr_write(d10kb[d10ks..@intCast(usize, 19)]);
        var d10mc: []const u8 = "c"; pal.stderr_write(d10mc);
        var d10cb: [20]u8 = undefined; var d10cl = itoa_mod.itoa(cond_temp, d10cb[0..]); var d10cs: usize = @intCast(usize, 19) - @intCast(usize, d10cl); pal.stderr_write(d10cb[d10cs..@intCast(usize, 19)]);
        var d10t: []const u8 = "t"; pal.stderr_write(d10t);
        var d10tb: [20]u8 = undefined; var d10tl = itoa_mod.itoa(self.hoisted_temps.items[@intCast(usize, cond_temp)].type_id, d10tb[0..]); var d10ts: usize = @intCast(usize, 19) - @intCast(usize, d10tl); pal.stderr_write(d10tb[d10ts..@intCast(usize, 19)]);
        var d10nl: []const u8 = "\n"; pal.stderr_write(d10nl);
        }
        var then_bb = createBlock(self);
        var else_bb: u32 = 0;
        var join_bb = createBlock(self);
        if (node.child_2 != 0) {
            else_bb = createBlock(self);
        }
        var fallthrough = if (else_bb != 0) else_bb else join_bb;
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = then_bb, .else_bb = fallthrough } });
        self.current_bb = then_bb;
        self.block_terminated = @intCast(u8, 0);
        lowerStmtBody(self, node.child_1);
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        if (else_bb != 0) {
            self.current_bb = else_bb;
            self.block_terminated = @intCast(u8, 0);
            lowerStmtBody(self, node.child_2);
            if (self.block_terminated == @intCast(u8, 0)) {
                emitInst(self, LirInst{ .jump = join_bb });
            }
        }
        self.current_bb = join_bb;
    } else if (node.kind == AstKind.while_stmt) {
        var entry_bb = self.current_bb;
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
        markTerminated(&self.func.blocks, entry_bb);
        self.current_bb = cond_bb;
        var cond_temp = lowerExpr(self, node.child_0);
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = body_bb, .else_bb = exit_bb } });
        self.current_bb = body_bb;
        self.block_terminated = @intCast(u8, 0);
        lowerStmtBody(self, node.child_1);
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = cond_bb });
        }
        self.current_bb = exit_bb;
        self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
     } else if (node.kind == AstKind.for_stmt) {
          var pattern = store.nodes.items[@intCast(usize, node.child_0)];
          var elem_type: [1]u32 = [1]u32{type_mod.TYPE_U32};
           var pat_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
           var a6_m: []const u8 = "A6:"; pal.stderr_write(a6_m);
           var a6_cb: [20]u8 = undefined; var a6_cl = itoa_mod.itoa(node.child_0, a6_cb[0..]); var a6_cs: usize = @intCast(usize, 19) - @intCast(usize, a6_cl); pal.stderr_write(a6_cb[a6_cs..@intCast(usize, 19)]);
           if (pat_type) |pt| {
               var a6_hm: []const u8 = "H"; pal.stderr_write(a6_hm);
               var a6_hb: [20]u8 = undefined; var a6_hl = itoa_mod.itoa(pt, a6_hb[0..]); var a6_hs: usize = @intCast(usize, 19) - @intCast(usize, a6_hl); pal.stderr_write(a6_hb[a6_hs..@intCast(usize, 19)]);
              var pt_ty = self.ctx.registry.types_items[@intCast(usize, pt)];
              if (pt_ty.kind == type_mod.TypeKind.slice_type) {
                  var sp = self.ctx.registry.slice_items[@intCast(usize, pt_ty.payload_idx)];
                  elem_type[0] = sp.elem;
              } else if (pt_ty.kind == type_mod.TypeKind.array_type) {
                  var ap = self.ctx.registry.array_items[@intCast(usize, pt_ty.payload_idx)];
                  elem_type[0] = ap.elem;
              }
           } else {
               var a6_mm: []const u8 = "M"; pal.stderr_write(a6_mm);
           }
           if (node.child_2 != @intCast(u32, 0)) {
              var slice_temp = lowerExpr(self, node.child_0);
              var ptr_temp = nextTemp(self, type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, elem_type[0], false));
              var len_temp = nextTemp(self, type_mod.TYPE_USIZE);
            emitInst(self, LirInst{ .load_field = .{ .base = slice_temp, .field_id = @intCast(u32, 0), .result = ptr_temp } });
            emitInst(self, LirInst{ .load_field = .{ .base = slice_temp, .field_id = @intCast(u32, 1), .result = len_temp } });
             var idx_temp = nextTemp(self, type_mod.TYPE_USIZE);
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
              var item_temp = nextTemp(self, elem_type[0]);
              emitInst(self, LirInst{ .load_index = .{ .base = ptr_temp, .index = idx_temp, .result = item_temp } });
              if (node.child_2 != @intCast(u32, 0)) { addLocalDecl(self, node.payload, elem_type[0], item_temp); addLocalDecl(self, node.child_2, type_mod.TYPE_USIZE, idx_temp); }
            self.block_terminated = @intCast(u8, 0);
            lowerStmtBody(self, node.child_1);
            if (self.block_terminated == @intCast(u8, 0)) {
                var nxt_idx = nextTemp(self, type_mod.TYPE_USIZE);
                emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = idx_temp, .rhs = @intCast(u32, 1), .result = nxt_idx } });
                idx_temp = nxt_idx;
                emitInst(self, LirInst{ .jump = cond_bb });
            }
            self.current_bb = exit_bb;
            self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
    } else if (node.kind == AstKind.switch_expr) {
        var cond_temp = lowerExpr(self, node.child_0);
        var cond_ty_id = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (cond_ty_id) |ct| {
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .load_field = .{ .base = cond_temp, .field_id = @intCast(u32, 0), .result = tag_temp } });
                cond_temp = tag_temp;
            }
        }
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
                    var cval2: u64 = @intCast(u64, case_node.payload);
                    var cev2 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, @intCast(u32, case_ec[ci]));
                    if (cev2) |v| { cval2 = @intCast(u64, v); }
                    case_val = cval2;
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
            self.block_terminated = @intCast(u8, 1);
        }
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = store.nodes.items[@intCast(usize, prong_ec[pi])];
            var prong_bb_id = prong_start + @intCast(u32, pi);
            self.current_bb = prong_bb_id;
            self.block_terminated = @intCast(u8, 0);
            lowerStmtBody(self, prong_node.child_0);
            if (self.block_terminated == @intCast(u8, 0)) {
                emitInst(self, LirInst{ .jump = exit_bb });
            }
        }
        self.current_bb = exit_bb;
        } else {
            var start_temp = lowerExpr(self, pattern.child_0);
            if (node.payload != 0) addLocalDecl(self, node.payload, type_mod.TYPE_U32, start_temp);
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
            self.block_terminated = @intCast(u8, 0);
            lowerStmtBody(self, node.child_1);
            if (self.block_terminated == @intCast(u8, 0)) {
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
        if (self.block_terminated == @intCast(u8, 0)) {
            if (node.child_0 != 0) {
                var val = lowerExpr(self, node.child_0);
                var retm: []const u8 = "RET:v="; pal.stderr_write(retm); dbgPrintU32(val); var rett: []const u8 = " t="; pal.stderr_write(rett); dbgPrintU32(self.hoisted_temps.items[@intCast(usize, val)].type_id); var retn: []const u8 = "\n"; pal.stderr_write(retn);
                if (self.func.return_type != type_mod.TYPE_VOID) {
                    self.hoisted_temps.items[@intCast(usize, val)].type_id = self.func.return_type;
                }
                emitInst(self, LirInst{ .ret = val });
            } else {
                emitInst(self, LirInst{ .ret_void = {} });
            }
            self.block_terminated = @intCast(u8, 1);
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
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = exit_target });
            self.block_terminated = @intCast(u8, 1);
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
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = header_target });
            self.block_terminated = @intCast(u8, 1);
        }
    } else if (node.kind == AstKind.var_decl) {
        var name_id = node.payload;
        var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        if (node.child_0 != 0) {
            var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
            if (rt) |t| { decl_type = t; var vc: []const u8 = "VC"; pal.stderr_write(vc); }
            else { var vf: []const u8 = "VF"; pal.stderr_write(vf); }
        } else if (node.child_1 != 0) {
            var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_1);
            if (rt) |t| { decl_type = t; }
        }
        if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED)) {
            var dty = self.ctx.registry.types_items[@intCast(usize, decl_type)];
            if (dty.kind == type_mod.TypeKind.fn_type or dty.kind == type_mod.TypeKind.module_type) {
                var vb: []const u8 = "VB"; pal.stderr_write(vb);
            } else {
            var dl_temp = nextTemp(self, decl_type);
            emitInst(self, LirInst{ .decl_local = .{ .name_id = name_id, .type_id = decl_type, .temp = dl_temp } });
            addLocalDecl(self, name_id, decl_type, dl_temp);
            if (node.child_1 != 0) {
                var init_node = store.nodes.items[@intCast(usize, node.child_1)];
                var is_array_type: u8 = @intCast(u8, 0);
                var dt2 = self.ctx.registry.types_items[@intCast(usize, decl_type)];
                if (dt2.kind == type_mod.TypeKind.array_type) is_array_type = @intCast(u8, 1);
                if (is_array_type == @intCast(u8, 1) and init_node.kind == AstKind.array_init) {
                    var arr_temp = lowerExpr(self, node.child_1);
                    addLocalDecl(self, name_id, decl_type, arr_temp);
                } else if (is_array_type == @intCast(u8, 1) and init_node.kind == AstKind.undefined_literal) {
                    var arr_temp = nextTemp(self, decl_type);
                    addLocalDecl(self, name_id, decl_type, arr_temp);
                } else {
                    var init_val = lowerExpr(self, node.child_1);
                    emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = init_val } });
                }
            }
            }
        } else {
            var und: []const u8 = "NU";
            pal.stderr_write(und);
            if (node.child_1 != @intCast(u32, 0)) {
                var und2: []const u8 = "I";
                pal.stderr_write(und2);
                var init_node = store.nodes.items[@intCast(usize, node.child_1)];
                if (init_node.kind == AstKind.array_init) { var dk2: []const u8 = "a"; pal.stderr_write(dk2); }
                else if (init_node.kind == AstKind.struct_init) { var dk2: []const u8 = "s"; pal.stderr_write(dk2); }
                else { var dk2: []const u8 = "o"; pal.stderr_write(dk2); }
            }
            if (node.child_0 != @intCast(u32, 0)) {
                var und3: []const u8 = "T";
                pal.stderr_write(und3);
            }
            var und4: []const u8 = " ";
            pal.stderr_write(und4);
        }
    } else if (node.kind == AstKind.add_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.sub_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.mul_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.div_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_DIV, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.mod_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MOD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.shl_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.shr_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.and_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.xor_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XOR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else if (node.kind == AstKind.or_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_OR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var lhs_node = self.ctx.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var name_id = self.ctx.store.identifiers.items[@intCast(usize, lhs_node.payload)];
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = op_r } });
        } else {
            emitInst(self, LirInst{ .assign = .{ .dst = lhs_val, .src = op_r } });
        }
    } else {
        _ = lowerExpr(self, node_idx);
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
    var evcap = self.ctx.enum_value_table.capacity; var evcnt = self.ctx.enum_value_table.count;
    var evcap_buf: [20]u8 = undefined; var evcnt_buf: [20]u8 = undefined;
    var evcap_len = itoa_mod.itoa(@intCast(u32, evcap), evcap_buf[0..]);
    var evcnt_len = itoa_mod.itoa(@intCast(u32, evcnt), evcnt_buf[0..]);
    var evcap_s: usize = @intCast(usize, 19) - @intCast(usize, evcap_len);
    var evcnt_s: usize = @intCast(usize, 19) - @intCast(usize, evcnt_len);
    var lN: []const u8 = "lN="; pal.stderr_write(lN);
    pal.stderr_write(evcnt_buf[evcnt_s..@intCast(usize, 19)]);
    var lC: []const u8 = " lC="; pal.stderr_write(lC);
    pal.stderr_write(evcap_buf[evcap_s..@intCast(usize, 19)]);
    var lnl: []const u8 = "\n"; pal.stderr_write(lnl);
    var store = self.ctx.store;
    var node = store.nodes.items[@intCast(usize, fn_node)];
    var proto_idx = node.payload;
    var proto = store.fn_protos.items[@intCast(usize, proto_idx)];
    var func_raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, @sizeOf(LirFunction)), @intCast(usize, 4)) catch unreachable;
    var func_ptr = @ptrCast(*LirFunction, func_raw);
    func_ptr.name_id = proto.name_id;
    func_ptr.module_id = self.module_id;
    var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, proto.return_type_node);
    if (rt) |_| { var dr: []const u8 = "HR"; pal.stderr_write(dr); } else { var dr: []const u8 = "MR"; pal.stderr_write(dr); }
    func_ptr.return_type = if (rt) |tid| tid else type_mod.TYPE_VOID;
    func_ptr.params = lir_mod.lirParamArrayListInit(self.alloc);
    func_ptr.blocks = lir_mod.basicBlockArrayListInit(self.alloc);
    func_ptr.hoisted_temps = lir_mod.tempDeclArrayListInit(self.alloc);
    func_ptr.switch_cases = lir_mod.switchCaseArrayListInit(self.alloc);
    func_ptr.is_extern = @intCast(u8, if ((node.flags & @intCast(u8, 0x04)) != 0) 1 else 0);
    func_ptr.is_pub = @intCast(u8, if ((node.flags & @intCast(u8, 0x02)) != 0) 1 else 0);
    func_ptr.is_variadic = @intCast(u8, 0);
    var p_payload: u32 = (@intCast(u32, proto.params_start) << @intCast(u32, 16)) | @intCast(u32, proto.params_count);
    if (proto.params_count > @intCast(u16, 0)) {
        var pnodes = ast_mod.astStoreGetExtraChildren(store, p_payload);
        var pi: usize = @intCast(usize, 0);
        while (pi < pnodes.len) : (pi += @intCast(usize, 1)) {
            var pnode = store.nodes.items[@intCast(usize, pnodes[pi])];
            if (pnode.child_0 != @intCast(u32, 0)) {
                var p_name_id = pnode.payload;
                var p_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, pnode.child_0);
                if (p_type) |_| { var dp: []const u8 = "HP"; pal.stderr_write(dp); } else { var dp: []const u8 = "MP"; pal.stderr_write(dp); }
                var p_tid = if (p_type) |pt| pt else type_mod.TYPE_UNDEFINED;
                lir_mod.lirParamArrayListAppend(&func_ptr.params, lir_mod.LirParam{
                    .name_id = p_name_id,
                    .type_id = p_tid,
                });
                if (p_type) |pt| {
                    addLocalDecl(self, p_name_id, pt, 0);
                }
            } else {
                func_ptr.is_variadic = @intCast(u8, 1);
            }
        }
    }
    self.func = func_ptr;
    self.current_bb = createBlock(self);
    self.scope_depth = @intCast(u32, 0);
    self.temp_counter = @intCast(u32, 0);
    var body = node.child_0;
    if (body != 0) {
        self.block_terminated = @intCast(u8, 0);
        lowerStmtBody(self, body);
    }
    expandDefers(self, @intCast(u32, 0), @intCast(u8, 0));
    if (self.block_terminated == @intCast(u8, 0)) {
        emitInst(self, LirInst{ .ret_void = {} });
    }
    hoistTemps(self);
    var hi: usize = 0;
    var ht0: []const u8 = "D3HT:"; pal.stderr_write(ht0);
    while (hi < self.hoisted_temps.len) : (hi += 1) {
        var td = self.hoisted_temps.items[hi];
        dbgPrintU32(td.temp_id);
        var sp: []const u8 = ","; pal.stderr_write(sp);
        dbgPrintU32(td.type_id);
        if (hi + 1 < self.hoisted_temps.len) {
            var sep: []const u8 = "|"; pal.stderr_write(sep);
        }
    }
    var htnl: []const u8 = "\n"; pal.stderr_write(htnl);
    func_ptr.hoisted_temps = self.hoisted_temps;
    return func_ptr.*;
}
