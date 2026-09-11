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
const type_resolver = @import("type_resolver.zig");
const FieldEntry = @import("type_registry.zig").FieldEntry;
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const resolved_mod = @import("resolved_type_table.zig");
const CoercionTable = @import("coercion.zig").CoercionTable;
const CoercionEntry = @import("coercion.zig").CoercionEntry;
const CoercionKind = @import("coercion.zig").CoercionKind;
const coercion_mod = @import("coercion.zig");
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const diag_mod = @import("diagnostics.zig");
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

pub const SrcIntent = enum(u8) { value, null_src, error_src };

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
const BIN_WADD = @intCast(u8, 16);
const BIN_WSUB = @intCast(u8, 17);
const BIN_WMUL = @intCast(u8, 18);
const BIN_SADD = @intCast(u8, 19);
const BIN_SSUB = @intCast(u8, 20);
const BIN_SMUL = @intCast(u8, 21);
const BIN_SSHL = @intCast(u8, 22);
const UN_NEG   = @intCast(u8, 0);
const UN_NOT   = @intCast(u8, 1);
const UN_BNOT  = @intCast(u8, 2);
const UN_WNEG  = @intCast(u8, 3);
const TEMP_NONE: u32 = 0xFFFFFFFF;

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
    is_loop: u8,
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
    error_code_registry: *hash_mod.U32ToU32Map,
    call_arg_types: *hash_mod.U32ToU32Map,
    comptime_values: *hash_mod.U32ToU64Map,
    source_file_id: u32,
    safe_checks: bool,
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
    if (self.capacity > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.allocator,
            @ptrCast([*]u8, self.items),
            self.capacity * @sizeOf(DeferAction),
            new_cap * @sizeOf(DeferAction),
            @intCast(usize, 4));
        if (grown != null) {
            self.capacity = new_cap;
            return;
        }
    }
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
    if (self.capacity > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.allocator,
            @ptrCast([*]u8, self.items),
            self.capacity * @sizeOf(LoopInfo),
            new_cap * @sizeOf(LoopInfo),
            @intCast(usize, 4));
        if (grown != null) {
            self.capacity = new_cap;
            return;
        }
    }
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
    if (self.capacity > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.allocator,
            @ptrCast([*]u8, self.items),
            self.capacity * @sizeOf(SwitchInfo),
            new_cap * @sizeOf(SwitchInfo),
            @intCast(usize, 4));
        if (grown != null) {
            self.capacity = new_cap;
            return;
        }
    }
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

pub const ScopeNode = struct {
    parent: u32,
};

pub const ScopeNodeArrayList = struct {
    items: [*]ScopeNode,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn scopeNodeArrayListInit(allocator: *Sand) ScopeNodeArrayList {
    return ScopeNodeArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn scopeNodeArrayListEnsureCapacity(self: *ScopeNodeArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    if (self.capacity > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.allocator,
            @ptrCast([*]u8, self.items),
            self.capacity * @sizeOf(ScopeNode),
            new_cap * @sizeOf(ScopeNode),
            @intCast(usize, 4));
        if (grown != null) {
            self.capacity = new_cap;
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(ScopeNode) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]ScopeNode, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn scopeNodeArrayListAppend(self: *ScopeNodeArrayList, value: ScopeNode) void {
    scopeNodeArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn pushScope(self: *LirLowerer) u32 {
    scopeNodeArrayListAppend(&self.scope_nodes, ScopeNode{ .parent = self.cur_scope });
    self.cur_scope = @intCast(u32, self.scope_nodes.len - @intCast(usize, 1));
    return self.cur_scope;
}

pub fn createChildScope(self: *LirLowerer) u32 {
    scopeNodeArrayListAppend(&self.scope_nodes, ScopeNode{ .parent = self.cur_scope });
    return @intCast(u32, self.scope_nodes.len - @intCast(usize, 1));
}

pub fn scopeNodeForDepth(self: *LirLowerer, at_depth: u32) u32 {
    if (at_depth > self.scope_depth) {
        if (self.pending_scope == TEMP_NONE) {
            self.pending_scope = createChildScope(self);
        }
        return self.pending_scope;
    }
    return self.cur_scope;
}

pub fn pushScopeDepth(self: *LirLowerer) void {
    self.scope_depth += @intCast(u32, 1);
    if (self.pending_scope != TEMP_NONE) {
        self.cur_scope = self.pending_scope;
        self.pending_scope = TEMP_NONE;
    } else {
        _ = pushScope(self);
    }
}

pub fn popScopeDepth(self: *LirLowerer) void {
    self.scope_depth -= @intCast(u32, 1);
    self.cur_scope = self.scope_nodes.items[@intCast(usize, self.cur_scope)].parent;
}

pub const LocalBinding = struct {
    temp: u32,
    kind: u8,
    tid: u32,
};

fn dbgPrintU32(val: u32) void {
    var buf: [20]u8 = undefined;
    var len = itoa_mod.itoa(val, buf[0..]);
    var sbase: usize = @intCast(usize, 19) - @intCast(usize, len);
    var send: usize = @intCast(usize, 19);
    pal.markerWrite(buf[sbase .. send]);
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
    print_fn_id: u32,
    ptrcast_name_id: u32,
    ptrtoint_name_id: u32,
    inttoptr_name_id: u32,
    int_from_ptr_name_id: u32,
    ptr_from_int_name_id: u32,
    field_parent_ptr_name_id: u32,
    enumtoint_name_id: u32,
    inttoenum_name_id: u32,
    as_name_id: u32,
    bitcast_name_id: u32,
    size_of_name_id: u32,
    align_of_name_id: u32,
    offset_of_name_id: u32,
    bit_size_of_name_id: u32,
    bit_offset_of_name_id: u32,
    cvastart_name_id: u32,
    cvaarg_name_id: u32,
    cvaend_name_id: u32,
    putchar_name_id: u32,
    stdout_write_name_id: u32,
    stderr_write_name_id: u32,
    getchar_name_id: u32,
    exit_name_id: u32,
    panic_name_id: u32,
    sleep_ms_name_id: u32,
    is_windows_name_id: u32,
    console_clear_name_id: u32,
    console_gotoxy_name_id: u32,
    console_set_color_name_id: u32,
    local_decl_names: [*]u32,
    local_decl_src_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_temps: [*]u32,
    local_decl_kinds: [*]u8,
    local_decl_is_capture: [*]u8,
    local_decl_scopes: [*]u32,
    local_decl_scope_nodes: [*]u32,
    local_decl_fn: [*]u32,
    local_decl_cap: usize,
    local_decl_name_map: hash_mod.U32ToU32Map,
    local_decl_count: usize,
    scope_nodes: ScopeNodeArrayList,
    cur_scope: u32,
    pending_scope: u32,
    fn_seq: u32,
    _fn_ret_type: u32,
    _ctx_node_idx: u32,
    _ctx_node_kind: u32,
    capture_shadow: hash_mod.U32ToU32Map,
    synth_name_counter: u32,
    current_label: u32,

};

pub fn lowererInit(ctx: *SemanticContext, alloc: *Sand) LirLowerer {
    var intcast_s: []const u8 = "@intCast";
    var intcast_id = si_mod.stringInternerIntern(ctx.registry.interner, intcast_s);
    var inttofloat_s: []const u8 = "@intToFloat";
     var inttofloat_id = si_mod.stringInternerIntern(ctx.registry.interner, inttofloat_s);
     var print_s: []const u8 = "print";
     var print_id = si_mod.stringInternerIntern(ctx.registry.interner, print_s);
    var ptrcast_s: []const u8 = "@ptrCast";
    var ptrcast_id = si_mod.stringInternerIntern(ctx.registry.interner, ptrcast_s);
    var pti_s: []const u8 = "@ptrToInt";
    var ptin_id = si_mod.stringInternerIntern(ctx.registry.interner, pti_s);
    var itp_s: []const u8 = "@intToPtr";
    var itp_id = si_mod.stringInternerIntern(ctx.registry.interner, itp_s);
    var ifp_s: []const u8 = "@intFromPtr";
    var ifp_id = si_mod.stringInternerIntern(ctx.registry.interner, ifp_s);
    var pfi_s: []const u8 = "@ptrFromInt";
    var pfi_id = si_mod.stringInternerIntern(ctx.registry.interner, pfi_s);
    var fpp_s: []const u8 = "@fieldParentPtr";
    var fpp_id = si_mod.stringInternerIntern(ctx.registry.interner, fpp_s);
    var eit_s: []const u8 = "@enumToInt";
    var eit_id = si_mod.stringInternerIntern(ctx.registry.interner, eit_s);
    var ite_s: []const u8 = "@intToEnum";
    var ite_id = si_mod.stringInternerIntern(ctx.registry.interner, ite_s);
    var as_s: []const u8 = "@as";
    var as_id = si_mod.stringInternerIntern(ctx.registry.interner, as_s);
    var bc_s: []const u8 = "@bitCast";
    var bc_id = si_mod.stringInternerIntern(ctx.registry.interner, bc_s);
    var sizeof_s: []const u8 = "@sizeOf";
    var sizeof_id = si_mod.stringInternerIntern(ctx.registry.interner, sizeof_s);
    var alignof_s: []const u8 = "@alignOf";
    var alignof_id = si_mod.stringInternerIntern(ctx.registry.interner, alignof_s);
    var offsetof_s: []const u8 = "@offsetOf";
    var offsetof_id = si_mod.stringInternerIntern(ctx.registry.interner, offsetof_s);
    var bitsizeof_s: []const u8 = "@bitSizeOf";
    var bitsizeof_id = si_mod.stringInternerIntern(ctx.registry.interner, bitsizeof_s);
    var bitoffsetof_s: []const u8 = "@bitOffsetOf";
    var bitoffsetof_id = si_mod.stringInternerIntern(ctx.registry.interner, bitoffsetof_s);
    var cvastart_s: []const u8 = "@cVaStart";
    var cvastart_id = si_mod.stringInternerIntern(ctx.registry.interner, cvastart_s);
    var cvaarg_s: []const u8 = "@cVaArg";
    var cvaarg_id = si_mod.stringInternerIntern(ctx.registry.interner, cvaarg_s);
    var cvaend_s: []const u8 = "@cVaEnd";
    var cvaend_id = si_mod.stringInternerIntern(ctx.registry.interner, cvaend_s);
    var putchar_s: []const u8 = "@putChar";
    var putchar_id = si_mod.stringInternerIntern(ctx.registry.interner, putchar_s);
    var stdout_write_s: []const u8 = "@stdoutWrite";
    var stdout_write_id = si_mod.stringInternerIntern(ctx.registry.interner, stdout_write_s);
    var stderr_write_s: []const u8 = "@stderrWrite";
    var stderr_write_id = si_mod.stringInternerIntern(ctx.registry.interner, stderr_write_s);
    var getchar_s: []const u8 = "@getChar";
    var getchar_id = si_mod.stringInternerIntern(ctx.registry.interner, getchar_s);
    var exit_s: []const u8 = "@exit";
    var exit_id = si_mod.stringInternerIntern(ctx.registry.interner, exit_s);
    var panic_s: []const u8 = "@panic";
    var panic_id = si_mod.stringInternerIntern(ctx.registry.interner, panic_s);
    var sleep_ms_s: []const u8 = "@sleepMs";
    var sleep_ms_id = si_mod.stringInternerIntern(ctx.registry.interner, sleep_ms_s);
    var is_windows_s: []const u8 = "@isWindows";
    var is_windows_id = si_mod.stringInternerIntern(ctx.registry.interner, is_windows_s);
    var console_clear_s: []const u8 = "@consoleClear";
    var console_clear_id = si_mod.stringInternerIntern(ctx.registry.interner, console_clear_s);
    var console_gotoxy_s: []const u8 = "@consoleGotoxy";
    var console_gotoxy_id = si_mod.stringInternerIntern(ctx.registry.interner, console_gotoxy_s);
    var console_set_color_s: []const u8 = "@consoleSetColor";
    var console_set_color_id = si_mod.stringInternerIntern(ctx.registry.interner, console_set_color_s);
    var lowerer = LirLowerer{
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
         .print_fn_id = print_id,
         .ptrcast_name_id = ptrcast_id,
         .ptrtoint_name_id = ptin_id,
         .inttoptr_name_id = itp_id,
         .int_from_ptr_name_id = ifp_id,
         .ptr_from_int_name_id = pfi_id,
         .field_parent_ptr_name_id = fpp_id,
         .enumtoint_name_id = eit_id,
         .inttoenum_name_id = ite_id,
         .as_name_id = as_id,
         .bitcast_name_id = bc_id,
         .size_of_name_id = sizeof_id,
         .align_of_name_id = alignof_id,
         .offset_of_name_id = offsetof_id,
         .bit_size_of_name_id = bitsizeof_id,
         .bit_offset_of_name_id = bitoffsetof_id,
         .cvastart_name_id = cvastart_id,
         .cvaarg_name_id = cvaarg_id,
         .cvaend_name_id = cvaend_id,
         .putchar_name_id = putchar_id,
         .stdout_write_name_id = stdout_write_id,
         .stderr_write_name_id = stderr_write_id,
         .getchar_name_id = getchar_id,
         .exit_name_id = exit_id,
         .panic_name_id = panic_id,
         .sleep_ms_name_id = sleep_ms_id,
         .is_windows_name_id = is_windows_id,
         .console_clear_name_id = console_clear_id,
         .console_gotoxy_name_id = console_gotoxy_id,
         .console_set_color_name_id = console_set_color_id,
        .local_decl_names = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_src_names = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_types = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_temps = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_kinds = @ptrCast([*]u8, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 1), @intCast(usize, 4)) catch unreachable),
        .local_decl_is_capture = @ptrCast([*]u8, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 1), @intCast(usize, 4)) catch unreachable),
        .local_decl_scopes = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_scope_nodes = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_fn = @ptrCast([*]u32, alloc_mod.sandAlloc(alloc, @intCast(usize, 64) * @intCast(usize, 4), @intCast(usize, 4)) catch unreachable),
        .local_decl_cap = @intCast(usize, 64),
        .local_decl_name_map = hash_mod.u32ToU32MapInitCap(alloc, @intCast(usize, 64)),
        .local_decl_count = @intCast(usize, 0),
        .scope_nodes = scopeNodeArrayListInit(alloc),
        .cur_scope = @intCast(u32, 0),
        .pending_scope = TEMP_NONE,
        .fn_seq = @intCast(u32, 0),
        ._fn_ret_type = @intCast(u32, 0),
        ._ctx_node_idx = @intCast(u32, 0),
        ._ctx_node_kind = @intCast(u32, 0),
        .capture_shadow = hash_mod.u32ToU32MapInitCap(alloc, @intCast(usize, 32)),
        .synth_name_counter = @intCast(u32, 1),
        .current_label = @intCast(u32, 0),

    };
    scopeNodeArrayListAppend(&lowerer.scope_nodes, ScopeNode{ .parent = TEMP_NONE });
    lowerer.cur_scope = @intCast(u32, 0);
    return lowerer;
}

fn markTerminated(blocks: *lir_mod.BasicBlockArrayList, bb_id: u32) void {
    var ms: []const u8 = "MT"; pal.measureMarkerWrite(ms);
    var b = &blocks.items[@intCast(usize, bb_id)];
    b.is_terminated = @intCast(u8, 1);
    var me: []const u8 = "\n"; pal.measureMarkerWrite(me);
}

pub fn emitInst(self: *LirLowerer, inst: LirInst) void {
    lir_mod.lirInstArrayListAppend(&self.func.blocks.items[self.current_bb].insts, inst);
}

pub fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    var tid = self.temp_counter;
    var ctm: []const u8 = "CT:t"; pal.markerWrite(ctm);
    var ctb: [10]u8 = undefined; var ctl = itoa_mod.itoa(type_id, ctb[0..]); var cts: usize = @intCast(usize, 9) - @intCast(usize, ctl); pal.markerWrite(ctb[cts..@intCast(usize, 9)]);
    var ctrm: []const u8 = "r"; pal.markerWrite(ctrm);
    var ctrb: [10]u8 = undefined; var ctrl = itoa_mod.itoa(tid, ctrb[0..]); var ctrs: usize = @intCast(usize, 9) - @intCast(usize, ctrl); pal.markerWrite(ctrb[ctrs..@intCast(usize, 9)]);
    var ctnl: []const u8 = "\n"; pal.markerWrite(ctnl);
    if (type_id == type_mod.TYPE_UNDEFINED or type_id == type_mod.TYPE_VOID) {
        var nm: []const u8 = "NXT:i"; pal.markerWrite(nm);
        var ntb: [20]u8 = undefined; var ntl = itoa_mod.itoa(self._ctx_node_idx, ntb[0..]); var nts: usize = @intCast(usize, 19) - @intCast(usize, ntl); pal.markerWrite(ntb[nts..@intCast(usize, 19)]);
        var nkp: []const u8 = "k"; pal.markerWrite(nkp);
        var nkb: [20]u8 = undefined; var nkl = itoa_mod.itoa(self._ctx_node_kind, nkb[0..]); var nks: usize = @intCast(usize, 19) - @intCast(usize, nkl); pal.markerWrite(nkb[nks..@intCast(usize, 19)]);
        var ntp: []const u8 = "t"; pal.markerWrite(ntp);
        var ntpb: [20]u8 = undefined; var ntpl = itoa_mod.itoa(tid, ntpb[0..]); var ntps: usize = @intCast(usize, 19) - @intCast(usize, ntpl); pal.markerWrite(ntpb[ntps..@intCast(usize, 19)]);
        var nnl: []const u8 = " "; pal.markerWrite(nnl);
        if (type_id == type_mod.TYPE_VOID) {
            var vfnt_m: []const u8 = "VFLOW:ntv\n"; pal.markerWrite(vfnt_m);
        }
    }
    if (type_id == @intCast(u32, 1)) {
        var instb_nt_m: []const u8 = "INSTB:ntv\n"; pal.markerWrite(instb_nt_m);
    }
    if (type_id >= @intCast(u32, 18)) {
        var nxam: []const u8 = "NXA:t"; pal.markerWrite(nxam);
        var nxatb: [10]u8 = undefined; var nxatl = itoa_mod.itoa(tid, nxatb[0..]); var nxats: usize = @intCast(usize, 9) - @intCast(usize, nxatl); pal.markerWrite(nxatb[nxats..@intCast(usize, 9)]);
        var nxatm: []const u8 = "T"; pal.markerWrite(nxatm);
        var nxat2b: [10]u8 = undefined; var nxat2l = itoa_mod.itoa(type_id, nxat2b[0..]); var nxat2s: usize = @intCast(usize, 9) - @intCast(usize, nxat2l); pal.markerWrite(nxat2b[nxat2s..@intCast(usize, 9)]);
        var nxanm: []const u8 = "n"; pal.markerWrite(nxanm);
        var nxanb: [10]u8 = undefined; var nxanl = itoa_mod.itoa(self._ctx_node_idx, nxanb[0..]); var nxans: usize = @intCast(usize, 9) - @intCast(usize, nxanl); pal.markerWrite(nxanb[nxans..@intCast(usize, 9)]);
        var nxanl2: []const u8 = "\n"; pal.markerWrite(nxanl2);
    }
    self.temp_counter += @intCast(u32, 1);
    lir_mod.tempDeclArrayListAppend(&self.hoisted_temps, TempDecl{
        .temp_id = tid,
        .type_id = type_id,
    });
    return tid;
}

// A4F `-fsafe` cheap-check helpers. Each emits a backend-neutral
// `check_trap { cond, kind, aux, imm }` immediately before the guarded op; the
// emitter renders the concrete C guard. Gate at lowering so `-ffast` is
// unaffected (no new emission for div/shift/null).
fn emitSafeCheckDivMod(self: *LirLowerer, lhs: u32, rhs: u32) void {
    if (!self.ctx.safe_checks) return;
    var zt = nextTemp(self, type_mod.TYPE_U32);
    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = zt } });
    var cond = nextTemp(self, type_mod.TYPE_BOOL);
    emitInst(self, LirInst{ .binary = .{ .op = BIN_NE, .lhs = rhs, .rhs = zt, .result = cond } });
    emitInst(self, LirInst{ .check_trap = .{ .cond = cond, .kind = @intCast(u8, 2), .aux = lhs, .imm = @intCast(u64, rhs) } });
}

fn emitSafeCheckShift(self: *LirLowerer, lhs: u32, rhs: u32) void {
    if (!self.ctx.safe_checks) return;
    var lhs_ty = getTempType(self, lhs);
    var width = intCastTypeBits(self.ctx.registry, lhs_ty);
    if (width == @intCast(u32, 0)) return;
    var wt = nextTemp(self, type_mod.TYPE_USIZE);
    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, width), .result = wt } });
    var cond = nextTemp(self, type_mod.TYPE_BOOL);
    emitInst(self, LirInst{ .binary = .{ .op = BIN_LT, .lhs = rhs, .rhs = wt, .result = cond } });
    emitInst(self, LirInst{ .check_trap = .{ .cond = cond, .kind = @intCast(u8, 3), .aux = rhs, .imm = @intCast(u64, width) } });
}

// A6F `-fsafe` integer-overflow guard. Emits `check_trap{kind=6}` immediately
// before a guarded add/sub/mul/`<<`/unary-neg. `op` is a lir_mod.CHECK_OP_*;
// the emitter renders the short-circuit C guard from `aux` (lhs/operand) and
// `imm` (rhs; unused for unary neg) using `result_type`'s bound literals.
// Gated at lowering so `-ffast` emits nothing new; non-integer results
// (float/pointer/slice/bool) and width-0 types are skipped.
fn emitSafeCheckOverflow(self: *LirLowerer, op: u8, lhs: u32, rhs: u32, result_type: u32) void {
    if (!self.ctx.safe_checks) return;
    if (result_type == type_mod.TYPE_UNDEFINED or result_type == type_mod.TYPE_VOID) return;
    if (!type_mod.typeRegistryIsInteger(self.ctx.registry, result_type)) return;
    if (type_mod.typeRegistryIntWidthBits(self.ctx.registry, result_type) == @intCast(u8, 0)) return;
    emitInst(self, LirInst{ .check_trap = .{ .imm = @intCast(u64, rhs), .cond = @intCast(u32, 0), .aux = lhs, .result_type = result_type, .kind = @intCast(u8, 6), .op = op } });
}

fn emitSafeCheckNegate(self: *LirLowerer, operand: u32, result_type: u32) void {
    emitSafeCheckOverflow(self, lir_mod.CHECK_OP_NEG, operand, @intCast(u32, 0), result_type);
}

// A6F review-fix: a shift whose left operand is an integer literal lowers to a
// `TYPE_INT_LIT` temp with width 0, so neither the A4 count guard nor the A6F
// value guard can compute a bound (`1 << 40` / `2 << 31` silently wrapped under
// `-fsafe`). Under `-fsafe` only, materialize a typed temp for the literal LHS
// so both guards apply; `-ffast` is untouched (no new emission). The bound type
// is the shift node's coercion target when present (e.g. `var r: u32 = 1 << 31`
// -> u32, so a valid u32 shift is not false-trapped), else the shift's resolved
// type when it is a real integer, else i32.
fn materializeShiftLhs(self: *LirLowerer, node_idx: u32, lhs: u32, rtype: u32) u32 {
    if (!self.ctx.safe_checks) return lhs;
    if (getTempType(self, lhs) != type_mod.TYPE_INT_LIT) return lhs;
    var target: u32 = @intCast(u32, 0);
    if (coercion_mod.coercionTableGet(self.ctx.coercions, node_idx)) |ce| {
        if (ce.target_type != @intCast(u32, 0) and
            type_mod.typeRegistryIsInteger(self.ctx.registry, ce.target_type) and
            type_mod.typeRegistryIntWidthBits(self.ctx.registry, ce.target_type) != @intCast(u8, 0)) {
            target = ce.target_type;
        }
    }
    if (target == @intCast(u32, 0) and
        type_mod.typeRegistryIsInteger(self.ctx.registry, rtype) and
        type_mod.typeRegistryIntWidthBits(self.ctx.registry, rtype) != @intCast(u8, 0)) {
        target = rtype;
    }
    if (target == @intCast(u32, 0)) target = type_mod.TYPE_I32;
    var ct = nextTemp(self, target);
    emitInst(self, LirInst{ .int_cast = .{ .value = lhs, .target = target, .result = ct, .is_checked = @intCast(u8, 0) } });
    return ct;
}

// A5F `-fsafe` index out-of-bounds guard. Emits `check_trap{kind=5}` with
// `cond = idx < len` before a user `.load_index`/`.assign_index`. The length is
// compile-time `array_items[…].length` for arrays and `*[N]T` pointers-to-array,
// and a runtime `SLICE_FIELD_LEN` load from the *original* base temp (before
// `maybeExtractSlicePtr` drops the `.len`) for slices. `[*]T`/scalar pointers
// have no length and stay unchecked. A signed index wider than `usize` (e.g.
// i64 on -m32) additionally requires `idx >= 0`. Gated on `safe_checks` at
// lowering so `-ffast` emits nothing new.
fn indexStaticLenForType(reg: *type_mod.TypeRegistry, tid: u32) ?u32 {
    if (@intCast(usize, tid) >= reg.types_len) return null;
    var ty = reg.types_items[@intCast(usize, tid)];
    if (ty.kind == type_mod.TypeKind.array_type) {
        return reg.array_items[@intCast(usize, ty.payload_idx)].length;
    }
    if (ty.kind == type_mod.TypeKind.ptr_type) {
        var pointee = reg.ptr_items[@intCast(usize, ty.payload_idx)].base;
        if (@intCast(usize, pointee) < reg.types_len) {
            var pty = reg.types_items[@intCast(usize, pointee)];
            if (pty.kind == type_mod.TypeKind.array_type) {
                return reg.array_items[@intCast(usize, pty.payload_idx)].length;
            }
        }
    }
    return null;
}

// Recovers the compile-time array length of a `field_access` base whose temp
// decayed to a bare pointer (e.g. `s.arr` in `s.arr[i]`): resolve the
// container's declared type and the named field's declared type.
fn fieldStaticLenForBase(self: *LirLowerer, base_node: u32) ?u32 {
    var store = self.ctx.store;
    var bn = ast_mod.astStoreNodeAt(store, base_node);
    if (bn.kind != AstKind.field_access) return null;
    var field_name_id: u32 = ast_mod.astStoreNodePayload(store, base_node);
    var cid: u32 = undefined;
    if (resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, bn.child_0)) |ctv| {
        cid = ctv;
    } else return null;
    if (cid == type_mod.TYPE_UNDEFINED or cid == type_mod.TYPE_VOID) return null;
    if (@intCast(usize, cid) >= self.ctx.registry.types_len) return null;
    var cty = self.ctx.registry.types_items[@intCast(usize, cid)];
    if (cty.kind == type_mod.TypeKind.ptr_type or cty.kind == type_mod.TypeKind.many_ptr_type) {
        cid = self.ctx.registry.ptr_items[@intCast(usize, cty.payload_idx)].base;
        if (@intCast(usize, cid) >= self.ctx.registry.types_len) return null;
        cty = self.ctx.registry.types_items[@intCast(usize, cid)];
    }
    if (cty.kind != type_mod.TypeKind.struct_type and cty.kind != type_mod.TypeKind.union_type and cty.kind != type_mod.TypeKind.packed_union_type) return null;
    var fields: []FieldEntry = undefined;
    if (cty.kind == type_mod.TypeKind.union_type or cty.kind == type_mod.TypeKind.packed_union_type) {
        type_mod.typeRegistryGetUnionFields(self.ctx.registry, cid, &fields);
    } else {
        type_mod.typeRegistryGetStructFields(self.ctx.registry, cid, &fields);
    }
    var fi: usize = 0;
    while (fi < fields.len) : (fi += 1) {
        if (fields[fi].name_id == field_name_id) {
            return indexStaticLenForType(self.ctx.registry, fields[fi].type_id);
        }
    }
    return null;
}

fn emitSafeCheckIndex(self: *LirLowerer, orig_base: u32, base_node: u32, idx_temp: u32) void {
    if (!self.ctx.safe_checks) return;
    var reg = self.ctx.registry;
    var base_ty = getTempType(self, orig_base);
    var len_temp: u32 = @intCast(u32, 0);
    var len_static: u32 = @intCast(u32, 0);
    var have_len: u8 = @intCast(u8, 0);
    if (base_ty != type_mod.TYPE_UNDEFINED and base_ty != type_mod.TYPE_VOID and @intCast(usize, base_ty) < reg.types_len and reg.types_items[@intCast(usize, base_ty)].kind == type_mod.TypeKind.slice_type) {
        have_len = @intCast(u8, 1);
        len_temp = nextTemp(self, type_mod.TYPE_USIZE);
        var bnid = nameMapGet(self, orig_base);
        emitInst(self, LirInst{ .load_field = .{ .name_id = bnid, .base = orig_base, .field_id = type_mod.SLICE_FIELD_LEN, .result = len_temp } });
    } else if (indexStaticLenForType(reg, base_ty)) |sl| {
        have_len = @intCast(u8, 1);
        len_static = sl;
    } else if (resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, base_node)) |rt| {
        // An array-valued base (e.g. the field `s.arr` in `s.arr[i]`) can decay
        // to a bare pointer temp, losing its length; recover it from the base
        // node's declared type or the container's field declaration.
        // `[*]T`/scalar pointers still resolve to no length.
        if (indexStaticLenForType(reg, rt)) |sl2| {
            have_len = @intCast(u8, 1);
            len_static = sl2;
        } else if (fieldStaticLenForBase(self, base_node)) |fl| {
            have_len = @intCast(u8, 1);
            len_static = fl;
        }
    } else if (fieldStaticLenForBase(self, base_node)) |fl2| {
        have_len = @intCast(u8, 1);
        len_static = fl2;
    }
    if (have_len == @intCast(u8, 0)) return;
    var len_ref = len_temp;
    if (len_ref == @intCast(u32, 0)) {
        len_ref = nextTemp(self, type_mod.TYPE_USIZE);
        emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, len_static), .result = len_ref } });
    }
    var lt = nextTemp(self, type_mod.TYPE_BOOL);
    emitInst(self, LirInst{ .binary = .{ .op = BIN_LT, .lhs = idx_temp, .rhs = len_ref, .result = lt } });
    var cond = lt;
    var idx_ty = getTempType(self, idx_temp);
    var idx_bits = intCastTypeBits(reg, idx_ty);
    var usize_bits = intCastTypeBits(reg, type_mod.TYPE_USIZE);
    if (intCastTypeIsSigned(reg, idx_ty) != @intCast(u8, 0) and idx_bits > usize_bits) {
        var zero = nextTemp(self, idx_ty);
        emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = zero } });
        var nonneg = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_GE, .lhs = idx_temp, .rhs = zero, .result = nonneg } });
        cond = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = nonneg, .rhs = lt, .result = cond } });
    }
    var aux: u32 = @intCast(u32, 0);
    var imm: u64 = 0;
    if (len_temp != @intCast(u32, 0)) {
        aux = len_temp;
    } else {
        imm = @intCast(u64, len_static);
    }
    emitInst(self, LirInst{ .check_trap = .{ .cond = cond, .kind = @intCast(u8, 5), .aux = aux, .imm = imm } });
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
    var fmt_node = ast_mod.astStoreNodeAt(store, ec[0]);
    var string_id: u32 = ast_mod.astStoreNodePayload(store, ec[0]);
    emitInst(self, LirInst{ .print_str = .{ .string_id = string_id } });
    var tuple_node = ast_mod.astStoreNodeAt(store, ec[1]);
    var tuple_ec = ast_mod.astStoreNodeExtraChildren(store, ec[1]);
    var i: usize = 0;
    while (i < tuple_ec.len) : (i += 1) {
        var val = lowerExpr(self, tuple_ec[i]);
        emitInst(self, LirInst{ .print_val = .{ .value = val, .type_id = type_mod.TYPE_I32, .fmt = @intCast(u8, 'd') } });
    }
    return @intCast(u32, 0);
}

fn lowerPrintFmt(self: *LirLowerer, fmt_node_idx: u32, fmt: []const u8, arg_ec: []const u32) void {
    var seg_start: usize = @intCast(usize, 0);
    var ai: usize = @intCast(usize, 0);
    var i: usize = @intCast(usize, 0);
    while (i < fmt.len) : (i += @intCast(usize, 1)) {
        var c = fmt[i];
        var ip1: usize = i + @intCast(usize, 1);
        var nxt: u8 = @intCast(u8, 0);
        if (ip1 < fmt.len) { nxt = fmt[ip1]; }
        if (c == @intCast(u8, '{')) {
            if (nxt == @intCast(u8, '{')) {
                if (ip1 > seg_start) {
                    var sg1 = fmt[seg_start..ip1];
                    var sid1 = si_mod.stringInternerIntern(self.ctx.registry.interner, sg1);
                    emitInst(self, LirInst{ .print_str = .{ .string_id = sid1 } });
                }
                seg_start = i + @intCast(usize, 2);
                i += @intCast(usize, 1);
            } else {
                if (i > seg_start) {
                    var sg2 = fmt[seg_start..i];
                    var sid2 = si_mod.stringInternerIntern(self.ctx.registry.interner, sg2);
                    emitInst(self, LirInst{ .print_str = .{ .string_id = sid2 } });
                }
                if (ai < arg_ec.len) {
                    var pv = lowerExpr(self, arg_ec[ai]);
                    var pvt = self.hoisted_temps.items[@intCast(usize, pv)].type_id;
                    var spec_fmt: u8 = @intCast(u8, 'd');
                    var spec_i: usize = i + @intCast(usize, 1);
                    if (spec_i < fmt.len) {
                        var spec_c = fmt[spec_i];
                        if (spec_c != @intCast(u8, '}')) {
                            spec_fmt = spec_c;
                            if (spec_c != @intCast(u8, 'd') and spec_c != @intCast(u8, 'c') and spec_c != @intCast(u8, 's') and spec_c != @intCast(u8, 'x')) {
                                var fn_node = ast_mod.astStoreNodeAt(self.ctx.store, fmt_node_idx);
                                var isp = fn_node.span_start;
                                var iep = isp + @intCast(u32, fn_node.span_len);
                                var iv_msg: []const u8 = "invalid print format specifier";
                                _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0),
                                    @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3013_INVALID_PRINT_SPECIFIER)),
                                    self.ctx.source_file_id, isp, iep, iv_msg);
                            }
                        }
                    }
                    emitInst(self, LirInst{ .print_val = .{ .value = pv, .type_id = pvt, .fmt = spec_fmt } });
                    ai += @intCast(usize, 1);
                }
                var j: usize = i + @intCast(usize, 1);
                while (j < fmt.len) : (j += @intCast(usize, 1)) {
                    if (fmt[j] == @intCast(u8, '}')) break;
                }
                seg_start = j + @intCast(usize, 1);
                i = j;
            }
        } else if (c == @intCast(u8, '}')) {
            if (nxt == @intCast(u8, '}')) {
                if (ip1 > seg_start) {
                    var sg3 = fmt[seg_start..ip1];
                    var sid3 = si_mod.stringInternerIntern(self.ctx.registry.interner, sg3);
                    emitInst(self, LirInst{ .print_str = .{ .string_id = sid3 } });
                }
                seg_start = i + @intCast(usize, 2);
                i += @intCast(usize, 1);
            }
        }
    }
    if (fmt.len > seg_start) {
        var sg4 = fmt[seg_start..fmt.len];
        var sid4 = si_mod.stringInternerIntern(self.ctx.registry.interner, sg4);
        emitInst(self, LirInst{ .print_str = .{ .string_id = sid4 } });
    }
}

pub fn lowerExpr(self: *LirLowerer, node_idx: u32) u32 {
    var lex_node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    var lex_m: []const u8 = "LEX:n"; pal.markerWrite(lex_m);
    var lex_nb: [10]u8 = undefined; var lex_nl = itoa_mod.itoa(node_idx, lex_nb[0..]); var lex_ns: usize = @intCast(usize, 9) - @intCast(usize, lex_nl); pal.markerWrite(lex_nb[lex_ns..@intCast(usize, 9)]);
    var lex_km: []const u8 = "k"; pal.markerWrite(lex_km);
    var lex_kb: [10]u8 = undefined; var lex_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(lex_node.kind)), lex_kb[0..]); var lex_ks: usize = @intCast(usize, 9) - @intCast(usize, lex_kl); pal.markerWrite(lex_kb[lex_ks..@intCast(usize, 9)]);
    var lex_nl2: []const u8 = "\n"; pal.markerWrite(lex_nl2);
    var result = lowerExprImpl(self, node_idx);
    var ce = coercion_mod.coercionTableGet(self.ctx.coercions, node_idx);
    if (ce) |coercion| {
        var cep_m: []const u8 = "CEP:n"; pal.markerWrite(cep_m);
        var cep_nb: [10]u8 = undefined; var cep_nl = itoa_mod.itoa(node_idx, cep_nb[0..]); var cep_ns: usize = @intCast(usize, 9) - @intCast(usize, cep_nl); pal.markerWrite(cep_nb[cep_ns..@intCast(usize, 9)]);
        var cep_km: []const u8 = "k"; pal.markerWrite(cep_km);
        var cep_kb: [10]u8 = undefined; var cep_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(coercion.kind)), cep_kb[0..]); var cep_ks: usize = @intCast(usize, 9) - @intCast(usize, cep_kl); pal.markerWrite(cep_kb[cep_ks..@intCast(usize, 9)]);
        var cep_nl2: []const u8 = "\n"; pal.markerWrite(cep_nl2);
        result = applyCoercion(self, result, coercion);
    } else {
        var cem_m: []const u8 = "CEM:n"; pal.markerWrite(cem_m);
        var cem_nb: [10]u8 = undefined; var cem_nl = itoa_mod.itoa(node_idx, cem_nb[0..]); var cem_ns: usize = @intCast(usize, 9) - @intCast(usize, cem_nl); pal.markerWrite(cem_nb[cem_ns..@intCast(usize, 9)]);
        var cem_nl2: []const u8 = "\n"; pal.markerWrite(cem_nl2);
    }
    return result;
}

fn growLocalDecls(self: *LirLowerer) void {
    var new_cap: usize = if (self.local_decl_cap < @intCast(usize, 8)) @intCast(usize, 8) else self.local_decl_cap * @intCast(usize, 2);
    var raw_names = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_src_names = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_types = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_temps = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_kinds = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_is_capture = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 1) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_scopes = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_scope_nodes = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_fn = alloc_mod.sandAlloc(self.alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var ndst = @ptrCast([*]u32, raw_names);
    var ssdst = @ptrCast([*]u32, raw_src_names);
    var tdst = @ptrCast([*]u32, raw_types);
    var mdst = @ptrCast([*]u32, raw_temps);
    var kdst = @ptrCast([*]u8, raw_kinds);
    var icdst = @ptrCast([*]u8, raw_is_capture);
    var sdst = @ptrCast([*]u32, raw_scopes);
    var sndst = @ptrCast([*]u32, raw_scope_nodes);
    var fdst = @ptrCast([*]u32, raw_fn);
    if (self.local_decl_count > @intCast(usize, 0)) {
        var ci: usize = 0;
        while (ci < self.local_decl_count) : (ci += @intCast(usize, 1)) {
            ndst[ci] = self.local_decl_names[ci];
            ssdst[ci] = self.local_decl_src_names[ci];
            tdst[ci] = self.local_decl_types[ci];
            mdst[ci] = self.local_decl_temps[ci];
            kdst[ci] = self.local_decl_kinds[ci];
            icdst[ci] = self.local_decl_is_capture[ci];
            sdst[ci] = self.local_decl_scopes[ci];
            sndst[ci] = self.local_decl_scope_nodes[ci];
            fdst[ci] = self.local_decl_fn[ci];
        }
    }
    self.local_decl_names = ndst;
    self.local_decl_src_names = ssdst;
    self.local_decl_types = tdst;
    self.local_decl_temps = mdst;
    self.local_decl_kinds = kdst;
    self.local_decl_is_capture = icdst;
    self.local_decl_scopes = sdst;
    self.local_decl_scope_nodes = sndst;
    self.local_decl_fn = fdst;
    self.local_decl_cap = new_cap;
}

fn addLocalDecl(self: *LirLowerer, name_id: u32, type_id: u32, temp: u32, at_depth: u32, is_capture: u8) void {
    if (self.local_decl_count >= self.local_decl_cap) { growLocalDecls(self); }
    self.local_decl_names[self.local_decl_count] = name_id;
    self.local_decl_src_names[self.local_decl_count] = name_id;
    self.local_decl_types[self.local_decl_count] = type_id;
    self.local_decl_temps[self.local_decl_count] = temp;
    self.local_decl_kinds[self.local_decl_count] = @intCast(u8, @enumToInt(self.ctx.registry.types_items[@intCast(usize, type_id)].kind));
    self.local_decl_is_capture[self.local_decl_count] = is_capture;
    self.local_decl_scopes[self.local_decl_count] = at_depth;
    self.local_decl_scope_nodes[self.local_decl_count] = scopeNodeForDepth(self, at_depth);
    self.local_decl_fn[self.local_decl_count] = self.fn_seq;
    self.local_decl_count += @intCast(usize, 1);
    var adm: []const u8 = "AID:n"; pal.markerWrite(adm);
    var adnb: [10]u8 = undefined; var adnl = itoa_mod.itoa(name_id, adnb[0..]); var adns: usize = @intCast(usize, 9) - @intCast(usize, adnl); pal.markerWrite(adnb[adns..@intCast(usize, 9)]);
    var adtm: []const u8 = "t"; pal.markerWrite(adtm);
    var adtb: [10]u8 = undefined; var adtl = itoa_mod.itoa(temp, adtb[0..]); var adts: usize = @intCast(usize, 9) - @intCast(usize, adtl); pal.markerWrite(adtb[adts..@intCast(usize, 9)]);
    var adym: []const u8 = "Y"; pal.markerWrite(adym);
    var adyb: [10]u8 = undefined; var adyl = itoa_mod.itoa(type_id, adyb[0..]); var adys: usize = @intCast(usize, 9) - @intCast(usize, adyl); pal.markerWrite(adyb[adys..@intCast(usize, 9)]);
    var adcm: []const u8 = "c"; pal.markerWrite(adcm);
    var adc_nm: []const u8 = "ADC:n"; pal.markerWrite(adc_nm);
    var adc_nb: [10]u8 = undefined; var adc_nl = itoa_mod.itoa(name_id, adc_nb[0..]); var adc_ns: usize = @intCast(usize, 9) - @intCast(usize, adc_nl); pal.markerWrite(adc_nb[adc_ns..@intCast(usize, 9)]);
    var adc_tm: []const u8 = "t"; pal.markerWrite(adc_tm);
    var adc_tb: [10]u8 = undefined; var adc_tl = itoa_mod.itoa(type_id, adc_tb[0..]); var adc_ts: usize = @intCast(usize, 9) - @intCast(usize, adc_tl); pal.markerWrite(adc_tb[adc_ts..@intCast(usize, 9)]);
    var adc_nl2: []const u8 = "\n"; pal.markerWrite(adc_nl2);
}

fn addLocalDeclRenamed(self: *LirLowerer, src_name: u32, name_id: u32, type_id: u32, temp: u32, at_depth: u32, is_capture: u8) void {
    if (self.local_decl_count >= self.local_decl_cap) { growLocalDecls(self); }
    self.local_decl_names[self.local_decl_count] = name_id;
    self.local_decl_src_names[self.local_decl_count] = src_name;
    self.local_decl_types[self.local_decl_count] = type_id;
    self.local_decl_temps[self.local_decl_count] = temp;
    self.local_decl_kinds[self.local_decl_count] = @intCast(u8, @enumToInt(self.ctx.registry.types_items[@intCast(usize, type_id)].kind));
    self.local_decl_is_capture[self.local_decl_count] = is_capture;
    self.local_decl_scopes[self.local_decl_count] = at_depth;
    self.local_decl_scope_nodes[self.local_decl_count] = scopeNodeForDepth(self, at_depth);
    self.local_decl_fn[self.local_decl_count] = self.fn_seq;
    self.local_decl_count += @intCast(usize, 1);
    var adm: []const u8 = "AID:n"; pal.markerWrite(adm);
    var adnb: [10]u8 = undefined; var adnl = itoa_mod.itoa(name_id, adnb[0..]); var adns: usize = @intCast(usize, 9) - @intCast(usize, adnl); pal.markerWrite(adnb[adns..@intCast(usize, 9)]);
    var adtm: []const u8 = "t"; pal.markerWrite(adtm);
    var adtb: [10]u8 = undefined; var adtl = itoa_mod.itoa(temp, adtb[0..]); var adts: usize = @intCast(usize, 9) - @intCast(usize, adtl); pal.markerWrite(adtb[adts..@intCast(usize, 9)]);
    var adym: []const u8 = "Y"; pal.markerWrite(adym);
    var adyb: [10]u8 = undefined; var adyl = itoa_mod.itoa(type_id, adyb[0..]); var adys: usize = @intCast(usize, 9) - @intCast(usize, adyl); pal.markerWrite(adyb[adys..@intCast(usize, 9)]);
    var adcm: []const u8 = "c"; pal.markerWrite(adcm);
    var adc_nm: []const u8 = "ADC:n"; pal.markerWrite(adc_nm);
    var adc_nb: [10]u8 = undefined; var adc_nl = itoa_mod.itoa(name_id, adc_nb[0..]); var adc_ns: usize = @intCast(usize, 9) - @intCast(usize, adc_nl); pal.markerWrite(adc_nb[adc_ns..@intCast(usize, 9)]);
    var adc_tm: []const u8 = "t"; pal.markerWrite(adc_tm);
    var adc_tb: [10]u8 = undefined; var adc_tl = itoa_mod.itoa(type_id, adc_tb[0..]); var adc_ts: usize = @intCast(usize, 9) - @intCast(usize, adc_tl); pal.markerWrite(adc_tb[adc_ts..@intCast(usize, 9)]);
    var adc_nl2: []const u8 = "\n"; pal.markerWrite(adc_nl2);
}
fn synthName(self: *LirLowerer, name_id: u32) u32 {
    var orig_str = si_mod.stringInternerGet(self.ctx.registry.interner, name_id);
    var name_buf: [96]u8 = undefined;
    var np: usize = @intCast(usize, 0);
    while (np < orig_str.len and np < @intCast(usize, 95)) : (np += 1) { name_buf[np] = orig_str[np]; }
    name_buf[np] = @intCast(u8, '_'); np += 1;
    var sc = self.synth_name_counter; self.synth_name_counter = sc + @intCast(u32, 1);
    var scb: [16]u8 = undefined; var scl = itoa_mod.itoa(sc, scb[0..]);
    var sc_start: usize = @intCast(usize, 15) - @intCast(usize, scl);
    var sci: usize = sc_start;
    while (sci < sc_start + @intCast(usize, scl) and np < @intCast(usize, 95)) : (sci += 1) { name_buf[np] = scb[sci]; np += 1; }
    return si_mod.stringInternerIntern(self.ctx.registry.interner, name_buf[0..np]);
}

fn maybeDisambiguateCapture(self: *LirLowerer, capture_name: u32, variant_type_id: u32) u32 {
    var eli: usize = self.local_decl_count;
    while (eli > @intCast(usize, 0)) {
        eli -= @intCast(usize, 1);
        if (self.local_decl_names[eli] == capture_name) {
            var orig_str = si_mod.stringInternerGet(self.ctx.registry.interner, capture_name);
            var name_buf: [96]u8 = undefined;
            var np: usize = @intCast(usize, 0);
            while (np < orig_str.len and np < @intCast(usize, 95)) : (np += 1) { name_buf[np] = orig_str[np]; }
            name_buf[np] = @intCast(u8, '_'); np += 1;
            var sc = self.synth_name_counter; self.synth_name_counter = sc + @intCast(u32, 1);
            var scb: [16]u8 = undefined; var scl = itoa_mod.itoa(sc, scb[0..]);
            var sc_start: usize = @intCast(usize, 15) - @intCast(usize, scl);
            var sci: usize = sc_start;
            while (sci < sc_start + @intCast(usize, scl) and np < @intCast(usize, 95)) : (sci += 1) { name_buf[np] = scb[sci]; np += 1; }
            var syn_id = si_mod.stringInternerIntern(self.ctx.registry.interner, name_buf[0..np]);
            _ = hash_mod.u32ToU32MapPut(&self.capture_shadow, capture_name, syn_id);
            return syn_id;
        }
    }
    return capture_name;
}

fn maybeDisambiguateCaptureIfTypeDiffers(self: *LirLowerer, capture_name: u32, cap_type_id: u32) u32 {
    var eli: usize = self.local_decl_count;
    while (eli > @intCast(usize, 0)) {
        eli -= @intCast(usize, 1);
        if (self.local_decl_names[eli] == capture_name and self.local_decl_fn[eli] == self.fn_seq and self.local_decl_types[eli] != cap_type_id) {
            return synthName(self, capture_name);
        }
    }
    return capture_name;
}

fn iceInvalidIndex(self: *LirLowerer, what: []const u8, idx: u32, len: u32) void {
    var idx_buf: [10]u8 = undefined;
    var idx_l = itoa_mod.itoa(idx, idx_buf[0..]);
    var len_buf: [10]u8 = undefined;
    var len_l = itoa_mod.itoa(len, len_buf[0..]);
    var p0: []const u8 = "internal: invalid ";
    var p1: []const u8 = " index ";
    var p2: []const u8 = " (len ";
    var p3: []const u8 = ")";
    var idx_s: usize = @intCast(usize, 9) - @intCast(usize, idx_l);
    var len_s: usize = @intCast(usize, 9) - @intCast(usize, len_l);
    var parts: [7][]const u8 = [7][]const u8{ p0, what, p1, idx_buf[idx_s..@intCast(usize, 9)], p2, len_buf[len_s..@intCast(usize, 9)], p3 };
    var msg = diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, &parts[0], @intCast(u32, 7));
    var start: u32 = 0;
    var end: u32 = 0;
    if (@intCast(usize, self._ctx_node_idx) < self.ctx.store.nodes.len) {
        var node = ast_mod.astStoreNodeAt(self.ctx.store, self._ctx_node_idx);
        start = node.span_start;
        end = node.span_start + @intCast(u32, node.span_len);
    }
    diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), start, end, msg);
    diag_mod.diagnosticCollectorFlushAndExit(self.ctx.diag, @intCast(u32, 3));
}

fn iceUnresolvedComptime(self: *LirLowerer, node_idx: u32) void {
    var node_id_buf: [10]u8 = undefined;
    var node_id_l = itoa_mod.itoa(node_idx, node_id_buf[0..]);
    var p0: []const u8 = "internal: comptime value unresolved for @sizeOf/@alignOf (node ";
    var p1: []const u8 = ")";
    var node_id_s: usize = @intCast(usize, 9) - @intCast(usize, node_id_l);
    var parts: [3][]const u8 = [3][]const u8{ p0, node_id_buf[node_id_s..@intCast(usize, 9)], p1 };
    var msg = diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, &parts[0], @intCast(u32, 3));
    var start: u32 = 0;
    var end: u32 = 0;
    if (@intCast(usize, node_idx) < self.ctx.store.nodes.len) {
        var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
        start = node.span_start;
        end = node.span_start + @intCast(u32, node.span_len);
    }
    diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), start, end, msg);
    diag_mod.diagnosticCollectorFlushAndExit(self.ctx.diag, @intCast(u32, 3));
}

fn iceSliceUnsupported(self: *LirLowerer, node_idx: u32) void {
    var node_id_buf: [10]u8 = undefined;
    var node_id_l = itoa_mod.itoa(node_idx, node_id_buf[0..]);
    var p0: []const u8 = "internal: unsupported slice_expr form/base (node ";
    var p1: []const u8 = ")";
    var node_id_s: usize = @intCast(usize, 9) - @intCast(usize, node_id_l);
    var parts: [3][]const u8 = [3][]const u8{ p0, node_id_buf[node_id_s..@intCast(usize, 9)], p1 };
    var msg = diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, &parts[0], @intCast(u32, 3));
    var start: u32 = 0;
    var end: u32 = 0;
    if (@intCast(usize, node_idx) < self.ctx.store.nodes.len) {
        var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
        start = node.span_start;
        end = node.span_start + @intCast(u32, node.span_len);
    }
    diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), start, end, msg);
    diag_mod.diagnosticCollectorFlushAndExit(self.ctx.diag, @intCast(u32, 3));
}

fn iceFieldStoreUnsupported(self: *LirLowerer, node_idx: u32) void {
    var node_id_buf: [10]u8 = undefined;
    var node_id_l = itoa_mod.itoa(node_idx, node_id_buf[0..]);
    var p0: []const u8 = "internal: unsupported field-store base (node ";
    var p1: []const u8 = ")";
    var node_id_s: usize = @intCast(usize, 9) - @intCast(usize, node_id_l);
    var parts: [3][]const u8 = [3][]const u8{ p0, node_id_buf[node_id_s..@intCast(usize, 9)], p1 };
    var msg = diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, &parts[0], @intCast(u32, 3));
    var start: u32 = 0;
    var end: u32 = 0;
    if (@intCast(usize, node_idx) < self.ctx.store.nodes.len) {
        var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
        start = node.span_start;
        end = node.span_start + @intCast(u32, node.span_len);
    }
    diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), start, end, msg);
    diag_mod.diagnosticCollectorFlushAndExit(self.ctx.diag, @intCast(u32, 3));
}

fn iceAssignLValueUnsupported(self: *LirLowerer, node_idx: u32) void {
    var node_id_buf: [10]u8 = undefined;
    var node_id_l = itoa_mod.itoa(node_idx, node_id_buf[0..]);
    var p0: []const u8 = "internal: unsupported assignment l-value (node ";
    var p1: []const u8 = ")";
    var node_id_s: usize = @intCast(usize, 9) - @intCast(usize, node_id_l);
    var parts: [3][]const u8 = [3][]const u8{ p0, node_id_buf[node_id_s..@intCast(usize, 9)], p1 };
    var msg = diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, &parts[0], @intCast(u32, 3));
    var start: u32 = 0;
    var end: u32 = 0;
    if (@intCast(usize, node_idx) < self.ctx.store.nodes.len) {
        var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
        start = node.span_start;
        end = node.span_start + @intCast(u32, node.span_len);
    }
    diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), start, end, msg);
    diag_mod.diagnosticCollectorFlushAndExit(self.ctx.diag, @intCast(u32, 3));
}

fn iceAddrOfLValueUnsupported(self: *LirLowerer, node_idx: u32) void {
    var node_id_buf: [10]u8 = undefined;
    var node_id_l = itoa_mod.itoa(node_idx, node_id_buf[0..]);
    var p0: []const u8 = "internal: unsupported address-of l-value (node ";
    var p1: []const u8 = ")";
    var node_id_s: usize = @intCast(usize, 9) - @intCast(usize, node_id_l);
    var parts: [3][]const u8 = [3][]const u8{ p0, node_id_buf[node_id_s..@intCast(usize, 9)], p1 };
    var msg = diag_mod.diagnosticBuilderMakeMsg(self.ctx.diag.interner, &parts[0], @intCast(u32, 3));
    var start: u32 = 0;
    var end: u32 = 0;
    if (@intCast(usize, node_idx) < self.ctx.store.nodes.len) {
        var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
        start = node.span_start;
        end = node.span_start + @intCast(u32, node.span_len);
    }
    diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_9001_ICE)), @intCast(u32, 0), start, end, msg);
    diag_mod.diagnosticCollectorFlushAndExit(self.ctx.diag, @intCast(u32, 3));
}

fn lowerLValueAddr(self: *LirLowerer, lv_node_idx: u32, result_type: u32) u32 {
    var store = self.ctx.store;
    var lv_node = ast_mod.astStoreNodeAt(store, lv_node_idx);
    if (lv_node.kind == AstKind.index_access) {
        var base_temp = lowerExpr(self, lv_node.child_0);
        base_temp = maybeExtractSlicePtr(self, lv_node.child_0, base_temp);
        var idx_temp = lowerExpr(self, lv_node.child_1);
        var tid = nextTemp(self, result_type);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = base_temp, .rhs = idx_temp, .result = tid } });
        return tid;
    }
    if (lv_node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(store, lv_node_idx);
        var shadow = hash_mod.u32ToU32MapGet(&self.capture_shadow, name_id);
        if (shadow) |syn| { if (captureShadowShouldRedirect(self, name_id, syn)) { name_id = syn; } }
        name_id = resolveLocalSrcName(self, name_id);
        var is_local: bool = false;
        var loc_kind: u8 = @intCast(u8, 0);
        var li: usize = @intCast(usize, 0);
        while (li < self.local_decl_count) : (li += @intCast(usize, 1)) {
            if (self.local_decl_names[li] == name_id) { is_local = true; loc_kind = self.local_decl_kinds[li]; break; }
        }
        var is_agg: bool = (loc_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.array_type))) or (loc_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.slice_type))) or (loc_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.tagged_union_type))) or (loc_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.struct_type)));
        var operand_temp: u32 = TEMP_NONE;
        if (is_local and !is_agg) {
            if (findLocalTemp(self, name_id)) |temp| { operand_temp = temp; }
        } else {
            operand_temp = lowerExpr(self, lv_node_idx);
        }
        var tid = nextTemp(self, result_type);
        emitInst(self, LirInst{ .addr_of = .{ .operand = operand_temp, .result = tid } });
        return tid;
    }
    if (lv_node.kind == AstKind.deref) {
        return lowerExpr(self, lv_node.child_0);
    }
    if (lv_node.kind == AstKind.paren_expr) {
        return lowerLValueAddr(self, lv_node.child_0, result_type);
    }
    if (lv_node.kind == AstKind.field_access) {
        var field_name_id: u32 = ast_mod.astStoreNodePayload(store, lv_node_idx);
        var base_node_idx = lv_node.child_0;
        var base_resolved = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, base_node_idx);
        var base_ty = if (base_resolved) |bt| bt else type_mod.TYPE_VOID;
        var base_is_ptr: u8 = @intCast(u8, 0);
        if (base_ty != type_mod.TYPE_UNDEFINED and base_ty != type_mod.TYPE_VOID) {
            var bty = self.ctx.registry.types_items[@intCast(usize, base_ty)];
            if (bty.kind == type_mod.TypeKind.ptr_type or bty.kind == type_mod.TypeKind.many_ptr_type) {
                base_is_ptr = @intCast(u8, 1);
            }
        }
        var base_addr: u32 = TEMP_NONE;
        if (base_is_ptr == @intCast(u8, 1)) {
            base_addr = lowerExpr(self, base_node_idx);
        } else if (base_ty != type_mod.TYPE_UNDEFINED and base_ty != type_mod.TYPE_VOID) {
            var ptr_to_base = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, base_ty, false);
            base_addr = lowerLValueAddr(self, base_node_idx, ptr_to_base);
        }
        var pointee_ty = base_ty;
        if (base_is_ptr == @intCast(u8, 1)) {
            var bty = self.ctx.registry.types_items[@intCast(usize, base_ty)];
            pointee_ty = self.ctx.registry.ptr_items[@intCast(usize, bty.payload_idx)].base;
        }
        var pty = self.ctx.registry.types_items[@intCast(usize, pointee_ty)];
        var pkind = pty.kind;
        var field_id: u32 = @intCast(u32, 0);
        var found_f: u8 = @intCast(u8, 0);
        if (pkind == type_mod.TypeKind.struct_type) {
            var fields: []FieldEntry = undefined;
            type_mod.typeRegistryGetStructFields(self.ctx.registry, pointee_ty, &fields);
            var fi: usize = 0;
            while (fi < fields.len) : (fi += 1) {
                if (fields[fi].name_id == field_name_id) { field_id = @intCast(u32, fi); found_f = @intCast(u8, 1); break; }
            }
        } else if (pkind == type_mod.TypeKind.union_type) {
            var fields: []FieldEntry = undefined;
            type_mod.typeRegistryGetUnionFields(self.ctx.registry, pointee_ty, &fields);
            var fi: usize = 0;
            while (fi < fields.len) : (fi += 1) {
                if (fields[fi].name_id == field_name_id) { field_id = @intCast(u32, fi); found_f = @intCast(u8, 1); break; }
            }
        }
        if (found_f == @intCast(u8, 0)) {
            iceAddrOfLValueUnsupported(self, lv_node_idx);
        }
        var tid = nextTemp(self, result_type);
        emitInst(self, LirInst{ .addr_of_field = .{ .base = base_addr, .field_id = field_id, .result = tid } });
        return tid;
    }
    iceAddrOfLValueUnsupported(self, lv_node_idx);
    return @intCast(u32, 0);
}

fn lowerDerefStore(self: *LirLowerer, deref_node_idx: u32, value_temp: u32) void {
    var deref_node = ast_mod.astStoreNodeAt(self.ctx.store, deref_node_idx);
    var ptr_temp = lowerExpr(self, deref_node.child_0);
    emitInst(self, LirInst{ .store = .{ .ptr = ptr_temp, .value = value_temp } });
}

fn lowerCompoundLValueStore(self: *LirLowerer, node_idx: u32, lhs_val: u32, op_r: u32) void {
    _ = lhs_val;
    var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    lowerAssignLValue(self, node.child_0, op_r, node_idx);
}

fn lowerAssignLValue(self: *LirLowerer, lv_node_idx: u32, value_temp: u32, diag_node_idx: u32) void {
    var store = self.ctx.store;
    var lv_node = ast_mod.astStoreNodeAt(store, lv_node_idx);
    if (lv_node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(store, lv_node_idx);
        var shadow = hash_mod.u32ToU32MapGet(&self.capture_shadow, name_id);
        if (shadow) |syn| { if (captureShadowShouldRedirect(self, name_id, syn)) { name_id = syn; } }
        name_id = resolveLocalSrcName(self, name_id);
        if (isStorageGlobal(self, name_id)) {
            var gs_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, name_id);
            if (gs_sym) |gss2| {
                emitInst(self, LirInst{ .store_global = .{ .name_id = name_id, .module_id = gss2.module_id, .value = value_temp } });
            }
            return;
        }
        if (findLocalTemp(self, name_id)) |reg| {
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = reg, .src = value_temp } });
        } else {
            emitInst(self, LirInst{ .store_local = .{ .name_id = name_id, .value = value_temp } });
        }
    } else if (lv_node.kind == AstKind.index_access) {
        var base_temp = lowerExpr(self, lv_node.child_0);
        var ai_orig_base = base_temp;
        base_temp = maybeExtractSlicePtr(self, lv_node.child_0, base_temp);
        var idx_temp = lowerExpr(self, lv_node.child_1);
        emitSafeCheckIndex(self, ai_orig_base, lv_node.child_0, idx_temp);
        var ai_ni: u32 = @intCast(u32, 0);
        var src_ni = resolved_mod.resolvedSourceTableGet(self.ctx.resolved_types, lv_node.child_0);
        if (src_ni) |sn| {
            ai_ni = sn;
        } else {
        if (ast_mod.astStoreNodeAt(store, lv_node.child_0).kind == AstKind.ident_expr) {
            var c0_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, lv_node.child_0);
            var is_slice: u8 = @intCast(u8, 0);
            if (c0_rt) |t| { var c0_ty = self.ctx.registry.types_items[@intCast(usize, t)]; if (@enumToInt(c0_ty.kind) == @intCast(u32, @enumToInt(type_mod.TypeKind.slice_type))) { is_slice = @intCast(u8, 1); } }
            if (is_slice == @intCast(u8, 0)) { ai_ni = ast_mod.astStoreIdentifier(store, lv_node.child_0); }
        }
        }
        if (ast_mod.astStoreNodeAt(store, lv_node.child_0).kind == AstKind.ident_expr) {
            var ai_c0_name = ast_mod.astStoreIdentifier(store, lv_node.child_0);
            if (isStorageGlobal(self, ai_c0_name)) { ai_ni = @intCast(u32, 0); }
        }
        if (base_temp != ai_orig_base) { ai_ni = @intCast(u32, 0); }
        emitInst(self, LirInst{ .assign_index = .{ .name_id = ai_ni, .base = base_temp, .index = idx_temp, .src = value_temp } });
    } else if (lv_node.kind == AstKind.field_access) {
        lowerFieldStore(self, lv_node_idx, value_temp, diag_node_idx);
    } else if (lv_node.kind == AstKind.deref) {
        lowerDerefStore(self, lv_node_idx, value_temp);
    } else if (lv_node.kind == AstKind.paren_expr) {
        lowerAssignLValue(self, lv_node.child_0, value_temp, diag_node_idx);
    } else {
        iceAssignLValueUnsupported(self, diag_node_idx);
    }
}


fn lowerContainerOfAccess(self: *LirLowerer, base_node_idx: u32, out_tid: *u32) u8 {
    var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, base_node_idx);
    if (rt) |t| {
        var cid = t;
        if (cid == type_mod.TYPE_UNDEFINED or cid == type_mod.TYPE_VOID) return @intCast(u8, 0);
        var cty = self.ctx.registry.types_items[@intCast(usize, cid)];
        if (cty.kind == type_mod.TypeKind.ptr_type or cty.kind == type_mod.TypeKind.many_ptr_type) {
            cid = self.ctx.registry.ptr_items[@intCast(usize, cty.payload_idx)].base;
        }
        out_tid.* = cid;
        return @intCast(u8, 1);
    }
    return @intCast(u8, 0);
}

fn lowerPackedChainAnalyze(self: *LirLowerer, node_idx: u32, holder_out: *u32, off_out: *u32, width_out: *u32, depth_out: *u32, first_packed_out: *u32, leaf_field_ty_out: *u32) u8 {
    var store = self.ctx.store;
    var stack: [16]u32 = undefined;
    var depth: usize = @intCast(usize, 0);
    var cur: u32 = node_idx;
    while (true) {
        var cnode = ast_mod.astStoreNodeAt(store, cur);
        if (cnode.kind != AstKind.field_access) break;
        if (depth >= @intCast(usize, 16)) return @intCast(u8, 0);
        stack[depth] = cur;
        depth += @intCast(usize, 1);
        cur = cnode.child_0;
    }
    if (depth < @intCast(usize, 2)) return @intCast(u8, 0);
    var first_packed: usize = @intCast(usize, 0xFFFFFFFF);
    var sidx: usize = depth;
    while (sidx > @intCast(usize, 0)) {
        sidx -= @intCast(usize, 1);
        var cid: u32 = @intCast(u32, 0);
        if (lowerContainerOfAccess(self, ast_mod.astStoreNodeAt(store, stack[sidx]).child_0, &cid) == @intCast(u8, 0)) return @intCast(u8, 0);
        var cty = self.ctx.registry.types_items[@intCast(usize, cid)];
        if ((cty.kind == type_mod.TypeKind.struct_type or cty.kind == type_mod.TypeKind.packed_union_type) and (cty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
            first_packed = sidx;
            break;
        }
        if (sidx == @intCast(usize, 0)) return @intCast(u8, 0);
    }
    if (first_packed == @intCast(usize, 0xFFFFFFFF) or first_packed == @intCast(usize, 0)) return @intCast(u8, 0);
    var total_off: u32 = @intCast(u32, 0);
    var leaf_width: u32 = @intCast(u32, 0);
    var li: usize = first_packed;
    while (true) {
        var cid: u32 = @intCast(u32, 0);
        if (lowerContainerOfAccess(self, ast_mod.astStoreNodeAt(store, stack[li]).child_0, &cid) == @intCast(u8, 0)) return @intCast(u8, 0);
        var cty = self.ctx.registry.types_items[@intCast(usize, cid)];
        var is_packed_struct: u8 = @intCast(u8, 0);
        var is_packed_union: u8 = @intCast(u8, 0);
        if (cty.kind == type_mod.TypeKind.struct_type and (cty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
            is_packed_struct = @intCast(u8, 1);
        } else if (cty.kind == type_mod.TypeKind.packed_union_type) {
            is_packed_union = @intCast(u8, 1);
        } else {
            return @intCast(u8, 0);
        }
        var fields: []FieldEntry = undefined;
        var pk_fields: []type_mod.PackedBitField = undefined;
        if (is_packed_struct == @intCast(u8, 1)) {
            type_mod.typeRegistryGetStructFields(self.ctx.registry, cid, &fields);
            if (!type_mod.typeRegistryGetPackedBitFields(self.ctx.registry, cid, &pk_fields)) return @intCast(u8, 0);
        } else {
            type_mod.typeRegistryGetUnionFields(self.ctx.registry, cid, &fields);
            if (!type_mod.typeRegistryGetPackedUnionBitFields(self.ctx.registry, cid, &pk_fields)) return @intCast(u8, 0);
        }
        var fname = ast_mod.astStoreNodePayload(store, stack[li]);
        var fi2: usize = @intCast(usize, 0);
        var found_off: u8 = @intCast(u8, 0);
        while (fi2 < fields.len) : (fi2 += @intCast(usize, 1)) {
            if (fields[fi2].name_id == fname and fi2 < pk_fields.len) {
                total_off += pk_fields[fi2].bit_offset;
                if (li == @intCast(usize, 0)) {
                    leaf_width = @intCast(u32, pk_fields[fi2].bit_width);
                    leaf_field_ty_out.* = fields[fi2].type_id;
                }
                found_off = @intCast(u8, 1);
                break;
            }
        }
        if (found_off == @intCast(u8, 0)) return @intCast(u8, 0);
        if (li == @intCast(usize, 0)) break;
        li -= @intCast(usize, 1);
    }
    if (leaf_width == @intCast(u32, 0)) return @intCast(u8, 0);
    var holder: u32 = cur;
    if (first_packed + @intCast(usize, 1) < depth) holder = stack[first_packed + @intCast(usize, 1)];
    holder_out.* = holder;
    off_out.* = total_off;
    width_out.* = leaf_width;
    depth_out.* = @intCast(u32, depth);
    first_packed_out.* = @intCast(u32, first_packed);
    return @intCast(u8, 1);
}

fn lowerTryNestedPackedLeafRead(self: *LirLowerer, node_idx: u32) u32 {
    var holder: u32 = @intCast(u32, 0);
    var off: u32 = @intCast(u32, 0);
    var width: u32 = @intCast(u32, 0);
    var depth: u32 = @intCast(u32, 0);
    var first_packed: u32 = @intCast(u32, 0);
    var leaf_field_ty: u32 = @intCast(u32, 0);
    if (lowerPackedChainAnalyze(self, node_idx, &holder, &off, &width, &depth, &first_packed, &leaf_field_ty) == @intCast(u8, 0)) return TEMP_NONE;
    if (leaf_field_ty < @intCast(u32, self.ctx.registry.types_len)) {
        var lf_ty = self.ctx.registry.types_items[@intCast(usize, leaf_field_ty)];
        if (lf_ty.kind == type_mod.TypeKind.struct_type and (lf_ty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
            var wsv_msg: []const u8 = "cannot read a whole packed-struct value out of a nested packed-struct field (bit-slice load not supported)";
            _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wsv_msg);
            return nextTemp(self, leaf_field_ty);
        }
    }
    var leaf_ty: u32 = @intCast(u32, 0);
    var got_leaf: u8 = @intCast(u8, 0);
    var lrt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
    if (lrt) |t| {
        if (t != type_mod.TYPE_UNDEFINED and t != type_mod.TYPE_VOID) {
            leaf_ty = t;
            got_leaf = @intCast(u8, 1);
        }
    }
    if (got_leaf == @intCast(u8, 0)) return TEMP_NONE;
    var base_temp = lowerExpr(self, holder);
    if (base_temp == TEMP_NONE or base_temp >= @intCast(u32, self.hoisted_temps.len)) return TEMP_NONE;
    var result_temp = nextTemp(self, leaf_ty);
    var sf_nid = nameMapGet(self, base_temp);
    emitInst(self, LirInst{ .load_bitfield = .{ .base = base_temp, .result = result_temp, .name_id = sf_nid, .bit_offset = off, .bit_width = width } });
    return result_temp;
}

fn lowerTryNestedPackedLeafStore(self: *LirLowerer, node_idx: u32, value_temp: u32, diag_node_idx: u32) u8 {
    _ = diag_node_idx;
    var holder: u32 = @intCast(u32, 0);
    var off: u32 = @intCast(u32, 0);
    var width: u32 = @intCast(u32, 0);
    var depth: u32 = @intCast(u32, 0);
    var first_packed: u32 = @intCast(u32, 0);
    var leaf_field_ty: u32 = @intCast(u32, 0);
    if (lowerPackedChainAnalyze(self, node_idx, &holder, &off, &width, &depth, &first_packed, &leaf_field_ty) == @intCast(u8, 0)) return @intCast(u8, 0);
    if (leaf_field_ty < @intCast(u32, self.ctx.registry.types_len)) {
        var lf_ty = self.ctx.registry.types_items[@intCast(usize, leaf_field_ty)];
        if (lf_ty.kind == type_mod.TypeKind.struct_type and (lf_ty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
            var wsv_msg: []const u8 = "cannot assign a whole packed-struct value to a nested packed-struct field (bit-slice store not supported)";
            _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wsv_msg);
            return @intCast(u8, 1);
        }
    }
    if (first_packed + @intCast(u32, 1) < depth) {
        var wps_msg: []const u8 = "cannot write a packed-struct leaf through a byte-aligned container field in a nested packed struct (unsupported store path)";
        _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wps_msg);
        return @intCast(u8, 1);
    }
    var base_temp = lowerExpr(self, holder);
    if (base_temp == TEMP_NONE or base_temp >= @intCast(u32, self.hoisted_temps.len)) return @intCast(u8, 0);
    emitInst(self, LirInst{ .store_bitfield = .{ .base = base_temp, .value = value_temp, .bit_offset = off, .bit_width = width } });
    return @intCast(u8, 1);
}

fn lowerFieldStore(self: *LirLowerer, fa_node_idx: u32, value_temp: u32, diag_node_idx: u32) void {
    var fa_node = ast_mod.astStoreNodeAt(self.ctx.store, fa_node_idx);
    var field_name_id: u32 = ast_mod.astStoreNodePayload(self.ctx.store, fa_node_idx);
    var child_0_node = ast_mod.astStoreNodeAt(self.ctx.store, fa_node.child_0);
    if (child_0_node.kind == AstKind.field_access) {
        if (lowerTryNestedPackedLeafStore(self, fa_node_idx, value_temp, diag_node_idx) != @intCast(u8, 0)) return;
    }
    if (child_0_node.kind == AstKind.ident_expr) {
        var cm_c0_name = ast_mod.astStoreIdentifier(self.ctx.store, fa_node.child_0);
        var cm_c0_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, cm_c0_name);
        if (cm_c0_sym) |cmcs| {
            if (cmcs.kind == sym_mod.SymbolKind.module) {
                var cm_tgt_mod = cmcs.module_id;
                var cm_mem_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, cm_tgt_mod, field_name_id);
                if (cm_mem_sym) |cmms| {
                    if (cmms.kind == sym_mod.SymbolKind.global) {
                        if ((@intCast(u16, cmms.flags) & @intCast(u16, 0x04)) == @intCast(u16, 0)) {
                            emitInst(self, LirInst{ .store_global = .{ .name_id = cmms.name_id, .module_id = cm_tgt_mod, .value = value_temp } });
                            return;
                        }
                    }
                }
            }
        }
    }
    var base_temp: u32 = undefined;
    var resolved_base: ?u32 = null;
    if (child_0_node.kind == AstKind.index_access) {
        var slice_temp = lowerExpr(self, child_0_node.child_0);
        var ptr_temp = maybeExtractSlicePtr(self, child_0_node.child_0, slice_temp);
        var idx_temp = lowerExpr(self, child_0_node.child_1);
        var elem_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, fa_node.child_0);
        var ptr_type = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, if (elem_type) |et| et else type_mod.TYPE_VOID, false);
        base_temp = nextTemp(self, ptr_type);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = ptr_temp, .rhs = idx_temp, .result = base_temp } });
        resolved_base = ptr_type;
    } else if (child_0_node.kind == AstKind.field_access or child_0_node.kind == AstKind.deref or child_0_node.kind == AstKind.paren_expr) {
        var nested_base_ty = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, fa_node.child_0);
        var nested_is_ptr: u8 = @intCast(u8, 0);
        if (nested_base_ty) |nbt| {
            if (nbt != type_mod.TYPE_UNDEFINED and nbt != type_mod.TYPE_VOID) {
                var nbty = self.ctx.registry.types_items[@intCast(usize, nbt)];
                if (nbty.kind == type_mod.TypeKind.ptr_type or nbty.kind == type_mod.TypeKind.many_ptr_type) {
                    nested_is_ptr = @intCast(u8, 1);
                }
            }
        }
        if (nested_is_ptr == @intCast(u8, 1)) {
            base_temp = lowerExpr(self, fa_node.child_0);
            resolved_base = nested_base_ty;
        } else {
            var ptr_type = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, if (nested_base_ty) |et| et else type_mod.TYPE_VOID, false);
            base_temp = lowerLValueAddr(self, fa_node.child_0, ptr_type);
            resolved_base = ptr_type;
        }
    } else {
        base_temp = lowerExpr(self, fa_node.child_0);
        resolved_base = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, fa_node.child_0);
    }

    if (resolved_base) |type_id| {
        var ty = self.ctx.registry.types_items[@intCast(usize, type_id)];
        var kind = ty.kind;
        var type_box: [1]u32 = [1]u32{type_id};
        if (kind == type_mod.TypeKind.ptr_type or kind == type_mod.TypeKind.many_ptr_type) {
            type_box[0] = self.ctx.registry.ptr_items[@intCast(usize, ty.payload_idx)].base;
            ty = self.ctx.registry.types_items[@intCast(usize, type_box[0])];
            kind = ty.kind;
        }
        if (kind == type_mod.TypeKind.struct_type) {
            var fields: []FieldEntry = undefined;
            type_mod.typeRegistryGetStructFields(self.ctx.registry, type_box[0], &fields);
            var fi: usize = 0;
            var field_id: u32 = @intCast(u32, 0);
            while (fi < fields.len) : (fi += 1) {
                if (fields[fi].name_id == field_name_id) {
                    field_id = @intCast(u32, fi);
                    break;
                }
            }
            var pk_fields: []type_mod.PackedBitField = undefined;
            if (type_mod.typeRegistryGetPackedBitFields(self.ctx.registry, type_box[0], &pk_fields)) {
                if (@intCast(usize, field_id) < pk_fields.len) {
                    if (@intCast(usize, field_id) < fields.len and fields[field_id].type_id < @intCast(u32, self.ctx.registry.types_len)) {
                        var mty = self.ctx.registry.types_items[@intCast(usize, fields[field_id].type_id)];
                        if (mty.kind == type_mod.TypeKind.struct_type and (mty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                            var wsv_msg: []const u8 = "cannot assign a whole packed-struct value to a nested packed-struct field (bit-slice store not supported)";
                            _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wsv_msg);
                            return;
                        }
                    }
                    var pkf = pk_fields[@intCast(usize, field_id)];
                    emitInst(self, LirInst{ .store_bitfield = .{ .base = base_temp, .value = value_temp, .bit_offset = pkf.bit_offset, .bit_width = @intCast(u32, pkf.bit_width) } });
                } else {
                    emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = field_id, .value = value_temp } });
                }
            } else {
                emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = field_id, .value = value_temp } });
            }
        } else if (kind == type_mod.TypeKind.slice_type) {
            var len_s: []const u8 = "len";
            var len_id = si_mod.stringInternerIntern(self.ctx.registry.interner, len_s);
            var sfid: u32 = if (field_name_id == len_id) type_mod.SLICE_FIELD_LEN else type_mod.SLICE_FIELD_PTR;
            emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = sfid, .value = value_temp } });
        } else if (kind == type_mod.TypeKind.tagged_union_type) {
            var tag_s: []const u8 = "tag";
            var tag_id = si_mod.stringInternerIntern(self.ctx.registry.interner, tag_s);
            var pay_s: []const u8 = "payload";
            var pay_id = si_mod.stringInternerIntern(self.ctx.registry.interner, pay_s);
            if (field_name_id == tag_id) {
                emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = type_mod.TU_FIELD_TAG, .value = value_temp } });
            } else if (field_name_id == pay_id) {
                emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = type_mod.TU_FIELD_PAYLOAD, .value = value_temp } });
            } else {
                iceFieldStoreUnsupported(self, diag_node_idx);
            }
        } else if (kind == type_mod.TypeKind.union_type or kind == type_mod.TypeKind.packed_union_type) {
            var fields: []FieldEntry = undefined;
            type_mod.typeRegistryGetUnionFields(self.ctx.registry, type_box[0], &fields);
            var fi: usize = 0;
            var field_id: u32 = @intCast(u32, 0);
            while (fi < fields.len) : (fi += 1) {
                if (fields[fi].name_id == field_name_id) {
                    field_id = @intCast(u32, fi);
                    break;
                }
            }
            if (kind == type_mod.TypeKind.packed_union_type) {
                var pk_fields: []type_mod.PackedBitField = undefined;
                if (type_mod.typeRegistryGetPackedUnionBitFields(self.ctx.registry, type_box[0], &pk_fields)) {
                    if (@intCast(usize, field_id) < pk_fields.len) {
                        if (@intCast(usize, field_id) < fields.len and fields[field_id].type_id < @intCast(u32, self.ctx.registry.types_len)) {
                            var mty = self.ctx.registry.types_items[@intCast(usize, fields[field_id].type_id)];
                            if (mty.kind == type_mod.TypeKind.struct_type and (mty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                                var wsv_msg: []const u8 = "cannot assign a whole packed-struct value to a packed union member (bit-slice store not supported)";
                                _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wsv_msg);
                                return;
                            }
                        }
                        var pkf = pk_fields[@intCast(usize, field_id)];
                        emitInst(self, LirInst{ .store_bitfield = .{ .base = base_temp, .value = value_temp, .bit_offset = pkf.bit_offset, .bit_width = @intCast(u32, pkf.bit_width) } });
                        return;
                    }
                }
            }
            emitInst(self, LirInst{ .store_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = field_id, .value = value_temp } });
        } else {
            iceFieldStoreUnsupported(self, diag_node_idx);
        }
    } else {
        iceFieldStoreUnsupported(self, diag_node_idx);
    }
}

fn lowerAppendSwitchCaseItem(self: *LirLowerer, item_idx: u32, prong_bb_id: u32, cond_ty_id: ?u32) void {
    var node = ast_mod.astStoreNodeAt(self.ctx.store, item_idx);
    if (node.kind == AstKind.range_inclusive or node.kind == AstKind.range_exclusive) {
        var lo_node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        var hi_node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_1);
        var lo_is_lit: u8 = @intCast(u8, 0);
        if (lo_node.kind == AstKind.int_literal or lo_node.kind == AstKind.char_literal) { lo_is_lit = @intCast(u8, 1); }
        var hi_is_lit: u8 = @intCast(u8, 0);
        if (hi_node.kind == AstKind.int_literal or hi_node.kind == AstKind.char_literal) { hi_is_lit = @intCast(u8, 1); }
        if (lo_is_lit == @intCast(u8, 1) and hi_is_lit == @intCast(u8, 1)) {
            var lo = ast_mod.astStoreIntValue(self.ctx.store, node.child_0);
            var hi = ast_mod.astStoreIntValue(self.ctx.store, node.child_1);
            if (hi >= lo) {
                var one: u64 = @intCast(u64, 1);
                var count: u64 = if (node.kind == AstKind.range_inclusive) (hi - lo) + one else hi - lo;
                if (count <= @intCast(u64, 16384)) {
                    var vv: u64 = lo;
                    var ctr: u64 = @intCast(u64, 0);
                    while (ctr < count) : (ctr += @intCast(u64, 1)) {
                        lir_mod.switchCaseArrayListAppend(&self.func.switch_cases, lir_mod.SwitchCase{ .value = vv, .target_bb = prong_bb_id });
                        vv += @intCast(u64, 1);
                    }
                }
            }
        }
        return;
    }
    var case_val: u64 = @intCast(u64, 0);
    if (node.kind == AstKind.int_literal) {
        case_val = ast_mod.astStoreIntValue(self.ctx.store, item_idx);
    } else if (node.kind == AstKind.char_literal) {
        case_val = ast_mod.astStoreIntValue(self.ctx.store, item_idx);
    } else if (node.kind == AstKind.enum_literal) {
        var cval2: u64 = @intCast(u64, ast_mod.astStoreNodePayload(self.ctx.store, item_idx));
        var cev2 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, item_idx);
        if (cev2) |v| { cval2 = @intCast(u64, v); }
        case_val = cval2;
    } else if (node.kind == AstKind.error_literal) {
        var cval3: u64 = @intCast(u64, hash_mod.u32ToU32MapGetOrAddDense(self.ctx.error_code_registry, ast_mod.astStoreNodePayload(self.ctx.store, item_idx)));
        var cev3 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, item_idx);
        if (cev3) |v| { cval3 = @intCast(u64, v); }
        case_val = cval3;
    } else if (node.kind == AstKind.field_access) {
        var fa_name_id: u32 = ast_mod.astStoreNodePayload(self.ctx.store, item_idx);
        var fa_found: bool = false;
        if (cond_ty_id) |ct| {
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.enum_type) {
                var ep = self.ctx.registry.en_items[@intCast(usize, ct_ty.payload_idx)];
                var estart: usize = @intCast(usize, ep.members_start);
                var ecount: usize = @intCast(usize, ep.members_count);
                var ei: usize = 0;
                while (ei < ecount) : (ei += 1) {
                    var member = self.ctx.registry.em_items[estart + ei];
                    if (member.name_id == fa_name_id) {
                        case_val = @intCast(u64, member.value);
                        fa_found = true;
                        break;
                    }
                }
            } else if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var tp = self.ctx.registry.tu_items[@intCast(usize, ct_ty.payload_idx)];
                var fstart: usize = @intCast(usize, tp.fields_start);
                var fcount: usize = @intCast(usize, tp.fields_count);
                var fi: usize = 0;
                while (fi < fcount) : (fi += 1) {
                    if (self.ctx.registry.fe_items[fstart + fi].name_id == fa_name_id) {
                        case_val = @intCast(u64, fi);
                        fa_found = true;
                        break;
                    }
                }
            }
        }
        if (!fa_found) { return; }
    } else {
        return;
    }
    lir_mod.switchCaseArrayListAppend(&self.func.switch_cases, lir_mod.SwitchCase{ .value = case_val, .target_bb = prong_bb_id });
}

fn getTempType(self: *LirLowerer, temp_id: u32) u32 {
    if (@intCast(usize, temp_id) >= self.hoisted_temps.len) {
        var ws: []const u8 = "temp";
        iceInvalidIndex(self, ws, temp_id, @intCast(u32, self.hoisted_temps.len));
        return @intCast(u32, 0);
    }
    return self.hoisted_temps.items[@intCast(usize, temp_id)].type_id;
}

fn intCastTypeBits(reg: *type_mod.TypeRegistry, tid: u32) u32 {
    if (tid == type_mod.TYPE_C_CHAR) { return @intCast(u32, 8); }
    if (tid == type_mod.TYPE_BOOL) { return @intCast(u32, 32); }
    if (type_mod.typeRegistryIsInteger(reg, tid)) {
        return @intCast(u32, type_mod.typeRegistryIntWidthBits(reg, tid));
    }
    if (tid == type_mod.TYPE_F32) { return @intCast(u32, 32); }
    if (tid == type_mod.TYPE_F64) { return @intCast(u32, 64); }
    return @intCast(u32, 0);
}

fn intCastTypeIsSigned(reg: *type_mod.TypeRegistry, tid: u32) u8 {
    if (tid == type_mod.TYPE_C_CHAR) return @intCast(u8, 1);
    if (tid == type_mod.TYPE_BOOL) return @intCast(u8, 0);
    if (type_mod.typeRegistryIntIsSigned(reg, tid)) return @intCast(u8, 1);
    return @intCast(u8, 0);
}

fn euPayloadOf(self: *LirLowerer, tid: u32) u32 {
    if (@intCast(usize, tid) >= self.ctx.registry.types_len) {
        var ws: []const u8 = "type";
        iceInvalidIndex(self, ws, tid, @intCast(u32, self.ctx.registry.types_len));
        return tid;
    }
    var ty = self.ctx.registry.types_items[@intCast(usize, tid)];
    if (ty.kind == type_mod.TypeKind.error_union_type) {
        if (@intCast(usize, ty.payload_idx) >= self.ctx.registry.eu_len) {
            var ws: []const u8 = "eu_payload";
            iceInvalidIndex(self, ws, ty.payload_idx, @intCast(u32, self.ctx.registry.eu_len));
            return tid;
        }
        var pay = self.ctx.registry.eu_items[@intCast(usize, ty.payload_idx)].payload;
        if (@intCast(usize, pay) >= self.ctx.registry.types_len) {
            var ws: []const u8 = "type";
            iceInvalidIndex(self, ws, pay, @intCast(u32, self.ctx.registry.types_len));
            return tid;
        }
        var payk = self.ctx.registry.types_items[@intCast(usize, pay)].kind;
        if (payk != type_mod.TypeKind.void_type) {
            return pay;
        }
    }
    return tid;
}

fn srcIntentFor(self: *LirLowerer, coercion: coercion_mod.CoercionEntry) SrcIntent {
    if (coercion.kind == CoercionKind.wrap_optional_null) return SrcIntent.null_src;
    if (coercion.kind == CoercionKind.wrap_error_err) return SrcIntent.error_src;
    var n = ast_mod.astStoreNodeAt(self.ctx.store, coercion.node_idx);
    if (n.kind == ast_mod.AstKind.null_literal) return SrcIntent.null_src;
    if (n.kind == ast_mod.AstKind.error_literal) return SrcIntent.error_src;
    return SrcIntent.value;
}

fn srcIntentForNode(self: *LirLowerer, node_idx: u32) SrcIntent {
    var n = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    if (n.kind == ast_mod.AstKind.null_literal) return SrcIntent.null_src;
    if (n.kind == ast_mod.AstKind.error_literal) return SrcIntent.error_src;
    return SrcIntent.value;
}

pub fn materializeInto(self: *LirLowerer, src_temp: u32, expected: u32, intent: SrcIntent) u32 {
    if (expected == @intCast(u32, 0) or expected == type_mod.TYPE_UNDEFINED) return src_temp;


    var src_ty = getTempType(self, src_temp);
    if (src_ty == expected) return src_temp;

    var layers: [8]u32 = undefined;
    var nlayers: usize = @intCast(usize, 0);
    var cur: u32 = expected;
    var guard: usize = @intCast(usize, 0);
    while (guard < @intCast(usize, 8)) : (guard += @intCast(usize, 1)) {
        if (@intCast(usize, cur) >= self.ctx.registry.types_len) {
            var ws: []const u8 = "type";
            iceInvalidIndex(self, ws, cur, @intCast(u32, self.ctx.registry.types_len));
            return src_temp;
        }
        var ck = self.ctx.registry.types_items[@intCast(usize, cur)];
        if (ck.kind == type_mod.TypeKind.optional_type) {
            layers[nlayers] = cur; nlayers += @intCast(usize, 1);
            if (intent == SrcIntent.null_src) break;
            if (@intCast(usize, ck.payload_idx) >= self.ctx.registry.opt_len) {
                var ws: []const u8 = "opt_payload";
                iceInvalidIndex(self, ws, ck.payload_idx, @intCast(u32, self.ctx.registry.opt_len));
                return src_temp;
            }
            var opl = self.ctx.registry.opt_items[@intCast(usize, ck.payload_idx)].payload;
            if (opl == src_ty) { cur = opl; break; }
            cur = opl; continue;
        }
        if (ck.kind == type_mod.TypeKind.error_union_type) {
            layers[nlayers] = cur; nlayers += @intCast(usize, 1);
            if (intent == SrcIntent.error_src) break;
            if (@intCast(usize, ck.payload_idx) >= self.ctx.registry.eu_len) {
                var ws: []const u8 = "eu_payload";
                iceInvalidIndex(self, ws, ck.payload_idx, @intCast(u32, self.ctx.registry.eu_len));
                return src_temp;
            }
            var eul = self.ctx.registry.eu_items[@intCast(usize, ck.payload_idx)].payload;
            if (eul == src_ty) { cur = eul; break; }
            cur = eul; continue;
        }
        break;
    }
    if (nlayers == @intCast(usize, 0)) return src_temp;

    var val = src_temp;
    if (intent == SrcIntent.value and cur != src_ty) {
        var nk = coercion_mod.classifyCoercion(self.ctx.registry, src_ty, cur);
        if (nk == CoercionKind.int_widen or nk == CoercionKind.int_literal_coerce) {
            var ct = nextTemp(self, cur);
            emitInst(self, LirInst{ .int_cast = .{ .value = val, .target = cur, .result = ct, .is_checked = @intCast(u8, 0) } });
            val = ct;
        } else if (nk == CoercionKind.float_widen) {
            var ft = nextTemp(self, cur);
            emitInst(self, LirInst{ .float_cast = .{ .value = val, .target = cur, .result = ft } });
            val = ft;
        }
    }

    var i: usize = nlayers;
    while (i > @intCast(usize, 0)) : (i -= @intCast(usize, 1)) {
        var layer = layers[i - @intCast(usize, 1)];
        var lk = self.ctx.registry.types_items[@intCast(usize, layer)].kind;
        var t = nextTemp(self, layer);
        if (lk == type_mod.TypeKind.error_union_type) {
            if (intent == SrcIntent.error_src) {
                emitInst(self, LirInst{ .wrap_error_err = .{ .value = val, .result = t, .type_id = layer } });
            } else {
                emitInst(self, LirInst{ .wrap_error_ok = .{ .value = val, .result = t, .type_id = layer } });
            }
        } else if (intent == SrcIntent.null_src and i == nlayers) {
            emitInst(self, LirInst{ .set_optional_null = .{ .result = t, .type_id = layer } });
        } else {
            emitInst(self, LirInst{ .wrap_optional = .{ .value = val, .result = t, .type_id = layer } });
        }
        val = t;
    }
    return val;
}


fn nameMapGet(self: *LirLowerer, temp_id: u32) u32 {
    var result = hash_mod.u32ToU32MapGet(&self.local_decl_name_map, temp_id);
    if (result) |v| return v;
    return TEMP_NONE;
}

fn resolveLocal(self: *LirLowerer, name_id: u32) ?LocalBinding {
    if (self.local_decl_count == @intCast(usize, 0)) return null;
    var scope: u32 = self.cur_scope;
    while (scope != TEMP_NONE) {
        var li: usize = self.local_decl_count;
        while (li > @intCast(usize, 0)) {
            li -= @intCast(usize, 1);
            if (self.local_decl_scope_nodes[li] == scope and self.local_decl_names[li] == name_id) {
                return LocalBinding{ .temp = self.local_decl_temps[li], .kind = self.local_decl_kinds[li], .tid = self.local_decl_types[li] };
            }
        }
        scope = self.scope_nodes.items[@intCast(usize, scope)].parent;
    }
    return null;
}

fn findLocalTemp(self: *LirLowerer, name_id: u32) ?u32 {
    var result = resolveLocal(self, name_id);
    if (result) |b| return b.temp;
    return null;
}

fn resolveLocalSrcName(self: *LirLowerer, name_id: u32) u32 {
    if (self.local_decl_count == @intCast(usize, 0)) return name_id;
    var li: usize = self.local_decl_count;
    while (li > @intCast(usize, 0)) {
        li -= @intCast(usize, 1);
        if (self.local_decl_src_names[li] == name_id and self.local_decl_fn[li] == self.fn_seq and self.local_decl_scopes[li] <= self.scope_depth) { return self.local_decl_names[li]; }
    }
    return name_id;
}

fn captureShadowShouldRedirect(self: *LirLowerer, name_id: u32, syn: u32) bool {
    var cap_scope: u32 = @intCast(u32, 0);
    var cap_idx: usize = @intCast(usize, 0);
    var cap_found: u8 = @intCast(u8, 0);
    var ci: usize = @intCast(usize, 0);
    while (ci < self.local_decl_count) : (ci += @intCast(usize, 1)) {
        if (self.local_decl_names[ci] == syn) { cap_scope = self.local_decl_scopes[ci]; cap_idx = ci; cap_found = @intCast(u8, 1); break; }
    }
    if (cap_found == @intCast(u8, 0)) return true;
    var si: usize = @intCast(usize, 0);
    while (si < self.local_decl_count) : (si += @intCast(usize, 1)) {
        if (self.local_decl_names[si] == name_id and si > cap_idx and self.local_decl_scopes[si] <= self.scope_depth and self.local_decl_scopes[si] >= cap_scope) return false;
    }
    return true;
}

fn vaListArgTemp(self: *LirLowerer, arg_node: u32) u32 {
    if (arg_node == @intCast(u32, 0)) return TEMP_NONE;
    var node = ast_mod.astStoreNodeAt(self.ctx.store, arg_node);
    if (node.kind == AstKind.address_of) {
        var inner = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        if (inner.kind == AstKind.ident_expr) {
            var nid = ast_mod.astStoreIdentifier(self.ctx.store, node.child_0);
            var fnd = findLocalTemp(self, nid);
            if (fnd) |t| return t;
        }
        return TEMP_NONE;
    }
    if (node.kind == AstKind.ident_expr) {
        var nid = ast_mod.astStoreIdentifier(self.ctx.store, arg_node);
        var fnd = findLocalTemp(self, nid);
        if (fnd) |t| return t;
    }
    return TEMP_NONE;
}

fn maybeExtractSlicePtr(self: *LirLowerer, base_node: u32, base_temp: u32) u32 {
    var resolved = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, base_node);
    var slice_tid_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
    if (resolved) |rt| {
        var rt_ty = self.ctx.registry.types_items[@intCast(usize, rt)];
        var mg1s: []const u8 = "MS:1\n"; pal.markerWrite(mg1s);
        if (rt_ty.kind == type_mod.TypeKind.slice_type) { slice_tid_box[0] = rt; }
    }
    if (slice_tid_box[0] != type_mod.TYPE_UNDEFINED) {
            var sp_ty = self.ctx.registry.types_items[@intCast(usize, slice_tid_box[0])];
            var sp = self.ctx.registry.slice_items[@intCast(usize, sp_ty.payload_idx)];
            var ptr_type = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, sp.elem, false);
             var ptr_temp = nextTemp(self, ptr_type);
               var base_nid = nameMapGet(self, base_temp);
               emitInst(self, LirInst{ .load_field = .{ .name_id = base_nid, .base = base_temp, .field_id = type_mod.SLICE_FIELD_PTR, .result = ptr_temp } });
             var slb_m: []const u8 = "SLB:b"; pal.markerWrite(slb_m);
             var slb_bb: [10]u8 = undefined; var slb_bl = itoa_mod.itoa(base_temp, slb_bb[0..]); var slb_bs: usize = @intCast(usize, 9) - @intCast(usize, slb_bl); pal.markerWrite(slb_bb[slb_bs..@intCast(usize, 9)]);
             var slb_rm: []const u8 = "r"; pal.markerWrite(slb_rm);
             var slb_rb: [10]u8 = undefined; var slb_rl = itoa_mod.itoa(ptr_temp, slb_rb[0..]); var slb_rs: usize = @intCast(usize, 9) - @intCast(usize, slb_rl); pal.markerWrite(slb_rb[slb_rs..@intCast(usize, 9)]);
             var slb_nl: []const u8 = "\n"; pal.markerWrite(slb_nl);
             var sla_m: []const u8 = "SLA:b"; pal.markerWrite(sla_m);
             var sla_bb: [10]u8 = undefined; var sla_bl = itoa_mod.itoa(base_temp, sla_bb[0..]); var sla_bs: usize = @intCast(usize, 9) - @intCast(usize, sla_bl); pal.markerWrite(sla_bb[sla_bs..@intCast(usize, 9)]);
             var sla_pm: []const u8 = "p"; pal.markerWrite(sla_pm);
             var sla_pb: [10]u8 = undefined; var sla_pl = itoa_mod.itoa(ptr_temp, sla_pb[0..]); var sla_ps: usize = @intCast(usize, 9) - @intCast(usize, sla_pl); pal.markerWrite(sla_pb[sla_ps..@intCast(usize, 9)]);
             var sla_nl: []const u8 = "\n"; pal.markerWrite(sla_nl);
             return ptr_temp;
        }
    return base_temp;
}

fn literalTempType(self: *LirLowerer, node_idx: u32) u32 {
    var ert = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
    if (ert) |t| { if (t != type_mod.TYPE_UNDEFINED and t != type_mod.TYPE_VOID) { return t; } }
    return type_mod.TYPE_INT_LIT;
}

fn emitTaggedUnionInit(self: *LirLowerer, tu_type_id: u32, variant_index: u32) u32 {
    var struct_tid = nextTemp(self, tu_type_id);
    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, variant_index), .result = struct_tid } });
    var tui_m: []const u8 = "TUI:t"; pal.markerWrite(tui_m);
    var tui_tb: [10]u8 = undefined; var tui_tl = itoa_mod.itoa(tu_type_id, tui_tb[0..]); var tui_ts: usize = @intCast(usize, 9) - @intCast(usize, tui_tl); pal.markerWrite(tui_tb[tui_ts..@intCast(usize, 9)]);
    var tui_im: []const u8 = "i"; pal.markerWrite(tui_im);
    var tui_ib: [10]u8 = undefined; var tui_il = itoa_mod.itoa(variant_index, tui_ib[0..]); var tui_is: usize = @intCast(usize, 9) - @intCast(usize, tui_il); pal.markerWrite(tui_ib[tui_is..@intCast(usize, 9)]);
    var tui_nl: []const u8 = "\n"; pal.markerWrite(tui_nl);
    return struct_tid;
}

fn bindOptionalCapture(self: *LirLowerer, capture_node: u32, cond_temp: u32) void {
    var cap = ast_mod.astStoreNodeAt(self.ctx.store, capture_node);
    var cap_name: u32 = ast_mod.astStoreNodePayload(self.ctx.store, capture_node);
    var cond_ty = getTempType(self, cond_temp);
    var ct = self.ctx.registry.types_items[@intCast(usize, cond_ty)];
    var pre_cap_type = cond_ty;
    if (ct.kind == type_mod.TypeKind.optional_type) {
        var opt_pay = self.ctx.registry.opt_items[@intCast(usize, ct.payload_idx)].payload;
        pre_cap_type = opt_pay;
    } else if (ct.kind == type_mod.TypeKind.tagged_union_type) {
        var tp = self.ctx.registry.tu_items[@intCast(usize, ct.payload_idx)];
        var payload_tid: u32 = @intCast(u32, type_mod.TYPE_VOID);
        var fi: usize = 0;
        while (fi < @intCast(usize, tp.fields_count)) : (fi += 1) {
            var fe = self.ctx.registry.fe_items[@intCast(usize, tp.fields_start) + fi];
            if (fe.type_id != type_mod.TYPE_VOID) { payload_tid = fe.type_id; break; }
        }
        pre_cap_type = payload_tid;
    }
    var cap_name_orig = cap_name;
    cap_name = maybeDisambiguateCaptureIfTypeDiffers(self, cap_name, pre_cap_type);
    var cap_type = cond_ty;
    var cap_temp = cond_temp;
    if (ct.kind == type_mod.TypeKind.optional_type) {
        var opt_pay = self.ctx.registry.opt_items[@intCast(usize, ct.payload_idx)].payload;
        var unwrapped = nextTemp(self, opt_pay);
        emitInst(self, LirInst{ .unwrap_optional = .{ .value = cond_temp, .result = unwrapped } });
        cap_type = opt_pay;
        cap_temp = unwrapped;
    } else if (ct.kind == type_mod.TypeKind.tagged_union_type) {
        var tp = self.ctx.registry.tu_items[@intCast(usize, ct.payload_idx)];
        var payload_tid: u32 = @intCast(u32, type_mod.TYPE_VOID);
        var fi: usize = 0;
        while (fi < @intCast(usize, tp.fields_count)) : (fi += 1) {
            var fe = self.ctx.registry.fe_items[@intCast(usize, tp.fields_start) + fi];
            if (fe.type_id != type_mod.TYPE_VOID) { payload_tid = fe.type_id; break; }
        }
        var payload_temp = nextTemp(self, payload_tid);
        emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = cond_temp, .field_id = type_mod.TU_FIELD_PAYLOAD, .result = payload_temp } });
        cap_type = payload_tid;
        cap_temp = payload_temp;
    } else {
        var bound = nextTemp(self, cond_ty);
        emitInst(self, LirInst{ .assign = .{ .dst = bound, .src = cond_temp, .name_id = cap_name } });
        cap_temp = bound;
    }
    if (cap_name != cap_name_orig) {
        addLocalDeclRenamed(self, cap_name_orig, cap_name, cap_type, cap_temp, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1));
    } else {
        addLocalDecl(self, cap_name, cap_type, cap_temp, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1));
    }
    emitInst(self, LirInst{ .decl_local = .{ .name_id = cap_name, .type_id = cap_type, .temp = cap_temp } });
}

fn isStorageGlobal(self: *LirLowerer, name_id: u32) bool {
    if (self.ctx.has_symbols == @intCast(u8, 0)) return false;
    var sg_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, name_id);
    if (sg_sym) |sgss| {
        if (sgss.kind == sym_mod.SymbolKind.global) {
            if ((@intCast(u16, sgss.flags) & @intCast(u16, 0x04)) != @intCast(u16, 0)) return false;
            return true;
        }
    }
    return false;
}

fn lowerGlobalRef(self: *LirLowerer, s: sym_mod.Symbol, name_id: u32) u32 {
    var lgr_m: []const u8 = "LGR:n"; pal.markerWrite(lgr_m);
    var lgr_b: [20]u8 = undefined; var lgr_l = itoa_mod.itoa(name_id, lgr_b[0..]); var lgr_s: usize = @intCast(usize, 19) - @intCast(usize, lgr_l); pal.markerWrite(lgr_b[lgr_s..@intCast(usize, 19)]);
    var lgr_nl: []const u8 = " "; pal.markerWrite(lgr_nl);
    var dn_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, s.decl_node);
    var tid_type = if (dn_type) |dt| dt else type_mod.TYPE_UNDEFINED;
    if ((@intCast(u16, s.flags) & @intCast(u16, 0x04)) != @intCast(u16, 0)) {
        var tid_e = nextTemp(self, tid_type);
        emitInst(self, LirInst{ .decl_local = .{ .name_id = name_id, .type_id = tid_type, .temp = tid_e } });
        return tid_e;
    }
    var tid = nextTemp(self, tid_type);
    emitInst(self, LirInst{ .load_global = .{ .name_id = name_id, .module_id = s.module_id, .result = tid } });
    return tid;
}


fn lowerExprImpl(self: *LirLowerer, node_idx: u32) u32 {
    self._ctx_node_idx = node_idx;
    self._ctx_node_kind = @intCast(u32, @enumToInt(ast_mod.astStoreNodeAt(self.ctx.store, node_idx).kind));
    var gb_im: []const u8 = "GBL:i"; pal.markerWrite(gb_im);
    var gb_ib: [10]u8 = undefined; var gb_il = itoa_mod.itoa(node_idx, gb_ib[0..]); var gb_is: usize = @intCast(usize, 9) - @intCast(usize, gb_il); pal.markerWrite(gb_ib[gb_is..@intCast(usize, 9)]);
    var gb_km: []const u8 = "k"; pal.markerWrite(gb_km);
    var gb_kb: [10]u8 = undefined; var gb_kl = itoa_mod.itoa(self._ctx_node_kind, gb_kb[0..]); var gb_ks: usize = @intCast(usize, 9) - @intCast(usize, gb_kl); pal.markerWrite(gb_kb[gb_ks..@intCast(usize, 9)]);
    var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
    if (rt) |trt| {
        var gb_h: []const u8 = "R"; pal.markerWrite(gb_h);
        var gb_rb: [10]u8 = undefined; var gb_rl = itoa_mod.itoa(trt, gb_rb[0..]); var gb_rs: usize = @intCast(usize, 9) - @intCast(usize, gb_rl); pal.markerWrite(gb_rb[gb_rs..@intCast(usize, 9)]);
    } else {
        var gb_m: []const u8 = "M"; pal.markerWrite(gb_m);
    }
    var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    var store = self.ctx.store;
    if (node.kind == AstKind.struct_init) {
        var bb_m: []const u8 = "BB:i"; pal.markerWrite(bb_m);
        var bb_ib: [10]u8 = undefined; var bb_il = itoa_mod.itoa(node_idx, bb_ib[0..]); var bb_is: usize = @intCast(usize, 9) - @intCast(usize, bb_il); pal.markerWrite(bb_ib[bb_is..@intCast(usize, 9)]);
        var bb_bm: []const u8 = "b"; pal.markerWrite(bb_bm);
        var bb_bb: [10]u8 = undefined; var bb_bl = itoa_mod.itoa(self.current_bb, bb_bb[0..]); var bb_bs: usize = @intCast(usize, 9) - @intCast(usize, bb_bl); pal.markerWrite(bb_bb[bb_bs..@intCast(usize, 9)]);
        var bb_nl: []const u8 = "\n"; pal.markerWrite(bb_nl);
    }
    var t_target: u32 = @intCast(u32, 10);
    if (node.kind == AstKind.int_literal) {
        var val = ast_mod.astStoreIntValue(self.ctx.store, node_idx);
        var tid = nextTemp(self, type_mod.TYPE_INT_LIT);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        var _rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var il_m: []const u8 = "ILR:i"; pal.markerWrite(il_m);
        var il_ib: [10]u8 = undefined; var il_il = itoa_mod.itoa(node_idx, il_ib[0..]); var il_is: usize = @intCast(usize, 9) - @intCast(usize, il_il); pal.markerWrite(il_ib[il_is..@intCast(usize, 9)]);
        var il_vm: []const u8 = "v"; pal.markerWriteInt64(il_vm, val);
        if (_rt) |trt| {
            var il_rm: []const u8 = "R"; pal.markerWrite(il_rm);
            var il_rb: [10]u8 = undefined; var il_rl = itoa_mod.itoa(trt, il_rb[0..]); var il_rs: usize = @intCast(usize, 9) - @intCast(usize, il_rl); pal.markerWrite(il_rb[il_rs..@intCast(usize, 9)]);
        } else {
            var il_mm: []const u8 = "M"; pal.markerWrite(il_mm);
        }
        var il_nl2: []const u8 = "\n"; pal.markerWrite(il_nl2);
        return tid;
    } else if (node.kind == AstKind.float_literal) {
        var val = store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(self.ctx.store, node_idx))];
        var tid = nextTemp(self, type_mod.TYPE_F64);
        emitInst(self, LirInst{ .float_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.string_literal) {
        var str_id = store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(self.ctx.store, node_idx))];
        var ptr_type = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, type_mod.TYPE_C_CHAR, true);
        var tid = nextTemp(self, ptr_type);
        emitInst(self, LirInst{ .string_const = .{ .string_id = str_id, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.char_literal) {
        var val = ast_mod.astStoreIntValue(self.ctx.store, node_idx);
        var tid = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bool_literal) {
        var val = @intCast(u8, node.flags & @intCast(u8, 1));
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .bool_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.null_literal) {
        var nul_ce = coercion_mod.coercionTableGet(self.ctx.coercions, node_idx);
        if (nul_ce) |nce| {
            var nul_routes_null: u8 = @intCast(u8, 0);
            if (nce.kind == CoercionKind.wrap_optional_null or nce.kind == CoercionKind.wrap_optional or nce.kind == CoercionKind.wrap_error_success) {
                nul_routes_null = @intCast(u8, 1);
            }
            if (nul_routes_null != @intCast(u8, 0) and nce.target_type != @intCast(u32, 0) and nce.target_type != type_mod.TYPE_UNDEFINED) {
                var opt_layer: u32 = @intCast(u32, 0);
                var cur_ty: u32 = nce.target_type;
                var walk_guard: usize = @intCast(usize, 0);
                while (walk_guard < @intCast(usize, 8)) : (walk_guard += @intCast(usize, 1)) {
                    if (@intCast(usize, cur_ty) >= self.ctx.registry.types_len) break;
                    var ck = self.ctx.registry.types_items[@intCast(usize, cur_ty)];
                    if (ck.kind == type_mod.TypeKind.optional_type) { opt_layer = cur_ty; break; }
                    if (ck.kind == type_mod.TypeKind.error_union_type) {
                        if (@intCast(usize, ck.payload_idx) >= self.ctx.registry.eu_len) break;
                        cur_ty = self.ctx.registry.eu_items[@intCast(usize, ck.payload_idx)].payload;
                        continue;
                    }
                    break;
                }
                if (opt_layer != @intCast(u32, 0)) {
                    var otid = nextTemp(self, opt_layer);
                    var nco_om: []const u8 = "NCO:opt"; pal.markerWriteInt(nco_om, otid);
                    var nco_ol: []const u8 = "\n"; pal.markerWrite(nco_ol);
                    emitInst(self, LirInst{ .set_optional_null = .{ .result = otid, .type_id = opt_layer } });
                    return otid;
                }
            }
        }
        var tid = nextTemp(self, type_mod.TYPE_NULL);
        var nco_m: []const u8 = "NCO:ti"; pal.markerWriteInt(nco_m, tid);
        var nco_nl: []const u8 = "\n"; pal.markerWrite(nco_nl);
        emitInst(self, LirInst{ .null_const = .{ .result = tid } });
        return tid;
    } else if (node.kind == AstKind.undefined_literal) {
        var tid = nextTemp(self, type_mod.TYPE_UNDEFINED);
        var und_ud_m: []const u8 = "UND:udLt"; pal.markerWrite(und_ud_m);
        var und_ud_tb: [10]u8 = undefined; var und_ud_tl = itoa_mod.itoa(tid, und_ud_tb[0..]); var und_ud_ts: usize = @intCast(usize, 9) - @intCast(usize, und_ud_tl); pal.markerWrite(und_ud_tb[und_ud_ts..@intCast(usize, 9)]);
        var und_ud_nl: []const u8 = "\n"; pal.markerWrite(und_ud_nl);
        emitInst(self, LirInst{ .undefined_const = .{ .result = tid, .type_id = type_mod.TYPE_UNDEFINED } });
        var uds_m: []const u8 = "UDS:t"; pal.markerWrite(uds_m);
        var uds_tb: [10]u8 = undefined; var uds_tl = itoa_mod.itoa(tid, uds_tb[0..]); var uds_ts: usize = @intCast(usize, 9) - @intCast(usize, uds_tl); pal.markerWrite(uds_tb[uds_ts..@intCast(usize, 9)]);
        var uds_nl: []const u8 = "\n"; pal.markerWrite(uds_nl);
        return tid;
    } else if (node.kind == AstKind.enum_literal) {
        var ev_val: u64 = @intCast(u64, ast_mod.astStoreNodePayload(self.ctx.store, node_idx));
        var evptr: u32 = @intCast(u32, @ptrToInt(self.ctx.enum_value_table));
        var evpb: [20]u8 = undefined;
        var evpl = itoa_mod.itoa(evptr, evpb[0..]);
        var evps: usize = @intCast(usize, 19) - @intCast(usize, evpl);
        var evR: []const u8 = "ER"; pal.markerWrite(evR);
        pal.markerWrite(evpb[evps..@intCast(usize, 19)]);
        var evgc2 = self.ctx.enum_value_table.count;
        var eg2b: [20]u8 = undefined;
        var eg2l = itoa_mod.itoa(@intCast(u32, evgc2), eg2b[0..]);
        var eg2s: usize = @intCast(usize, 19) - @intCast(usize, eg2l);
        var eRc: []const u8 = "c="; pal.markerWrite(eRc);
        pal.markerWrite(eg2b[eg2s..@intCast(usize, 19)]);
        var eRs: []const u8 = " "; pal.markerWrite(eRs);
        var ev = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, node_idx);
        var enum_type: [1]u32 = [1]u32{literalTempType(self, node_idx)};
        if (ev) |v| { ev_val = @intCast(u64, v); var we1: []const u8 = "WE"; pal.markerWrite(we1);
            var enum_ty = enum_type[0];
            if (enum_ty != type_mod.TYPE_INT_LIT and enum_ty != type_mod.TYPE_UNDEFINED and enum_ty != type_mod.TYPE_VOID) {
                var enum_ti = self.ctx.registry.types_items[@intCast(usize, enum_ty)];
                if (enum_ti.kind == type_mod.TypeKind.tagged_union_type) {
                    var tu_result = emitTaggedUnionInit(self, enum_ty, @intCast(u32, ev_val));
                    var enl_m: []const u8 = "ENL:t"; pal.markerWrite(enl_m);
                    var enl_tb: [10]u8 = undefined; var enl_tl = itoa_mod.itoa(enum_type[0], enl_tb[0..]); var enl_ts: usize = @intCast(usize, 9) - @intCast(usize, enl_tl); pal.markerWrite(enl_tb[enl_ts..@intCast(usize, 9)]);
                    var enl_cm: []const u8 = "c"; pal.markerWrite(enl_cm);
                    var enl_cb: [20]u8 = undefined; var enl_cl = itoa_mod.itoa(@intCast(u32, ev_val), enl_cb[0..]); var enl_cs: usize = @intCast(usize, 19) - @intCast(usize, enl_cl); pal.markerWrite(enl_cb[enl_cs..@intCast(usize, 19)]);
                    var enl_nl: []const u8 = "\n"; pal.markerWrite(enl_nl);
                    return tu_result;
                }
            }
        }
        else { var we1: []const u8 = "wE"; pal.markerWrite(we1); }
        var tid = nextTemp(self, enum_type[0]);
        emitInst(self, LirInst{ .int_const = .{ .value = ev_val, .result = tid } });
        var enl_m: []const u8 = "ENL:t"; pal.markerWrite(enl_m);
        var enl_tb: [10]u8 = undefined; var enl_tl = itoa_mod.itoa(enum_type[0], enl_tb[0..]); var enl_ts: usize = @intCast(usize, 9) - @intCast(usize, enl_tl); pal.markerWrite(enl_tb[enl_ts..@intCast(usize, 9)]);
        var enl_cm: []const u8 = "c"; pal.markerWrite(enl_cm);
        var enl_cb: [20]u8 = undefined; var enl_cl = itoa_mod.itoa(@intCast(u32, ev_val), enl_cb[0..]); var enl_cs: usize = @intCast(usize, 19) - @intCast(usize, enl_cl); pal.markerWrite(enl_cb[enl_cs..@intCast(usize, 19)]);
        var enl_nl: []const u8 = "\n"; pal.markerWrite(enl_nl);
        return tid;
    } else if (node.kind == AstKind.error_literal) {
        var name_id: u32 = ast_mod.astStoreNodePayload(self.ctx.store, node_idx);
        var reg_code: u32 = hash_mod.u32ToU32MapGetOrAddDense(self.ctx.error_code_registry, name_id);
        var val = @intCast(u64, reg_code);
        var ev = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, node_idx);
        if (ev) |v| { val = @intCast(u64, v); }
        var rtype = literalTempType(self, node_idx);
        var rty = self.ctx.registry.types_items[@intCast(usize, rtype)];
        if (rty.kind == type_mod.TypeKind.error_union_type) {
            var code_temp = nextTemp(self, type_mod.TYPE_I32);
            emitInst(self, LirInst{ .int_const = .{ .value = val, .result = code_temp } });
            var eu_temp = nextTemp(self, rtype);
            emitInst(self, LirInst{ .wrap_error_err = .{ .value = code_temp, .result = eu_temp, .type_id = rtype } });
            return eu_temp;
        }
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.unreachable_expr) {
        emitInst(self, LirInst{ .trap = {} });
        self.block_terminated = @intCast(u8, 1);
        return @intCast(u32, 0);
    } else if (node.kind == AstKind.paren_expr) {
        return lowerExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        return @intCast(u32, 0);
    } else if (node.kind == AstKind.add) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var lhs_type = getTempType(self, lhs);
        if (lhs_type != type_mod.TYPE_UNDEFINED) {
            var lty = self.ctx.registry.types_items[@intCast(usize, lhs_type)];
            if (lty.kind == type_mod.TypeKind.slice_type) {
                var am: []const u8 = "A:"; pal.markerWriteInt(am, lhs_type);
            }
        }
        var tid = nextTemp(self, rtype);
        var m4a_m: []const u8 = "M4a:r"; pal.markerWrite(m4a_m);
        var m4a_b: [20]u8 = undefined; var m4a_l = itoa_mod.itoa(rtype, m4a_b[0..]); var m4a_s: usize = @intCast(usize, 19) - @intCast(usize, m4a_l); pal.markerWrite(m4a_b[m4a_s..@intCast(usize, 19)]);
        var m4a_nl: []const u8 = "\n"; pal.markerWrite(m4a_nl);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_ADD, lhs, rhs, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.sub) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        var m4s_m: []const u8 = "M4s:r"; pal.markerWrite(m4s_m);
        var m4s_b: [20]u8 = undefined; var m4s_l = itoa_mod.itoa(rtype, m4s_b[0..]); var m4s_s: usize = @intCast(usize, 19) - @intCast(usize, m4s_l); pal.markerWrite(m4s_b[m4s_s..@intCast(usize, 19)]);
        var m4s_nl: []const u8 = "\n"; pal.markerWrite(m4s_nl);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_SUB, lhs, rhs, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.mul) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        var m4m_m: []const u8 = "M4m:r"; pal.markerWrite(m4m_m);
        var m4m_b: [20]u8 = undefined; var m4m_l = itoa_mod.itoa(rtype, m4m_b[0..]); var m4m_s: usize = @intCast(usize, 19) - @intCast(usize, m4m_l); pal.markerWrite(m4m_b[m4m_s..@intCast(usize, 19)]);
        var m4m_nl: []const u8 = "\n"; pal.markerWrite(m4m_nl);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_MUL, lhs, rhs, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MUL, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.wrap_add or node.kind == AstKind.wrap_sub or node.kind == AstKind.wrap_mul) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        if (node.kind == AstKind.wrap_add) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WADD, .lhs = lhs, .rhs = rhs, .result = tid } });
        } else if (node.kind == AstKind.wrap_sub) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WSUB, .lhs = lhs, .rhs = rhs, .result = tid } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WMUL, .lhs = lhs, .rhs = rhs, .result = tid } });
        }
        return tid;
    } else if (node.kind == AstKind.sat_add or node.kind == AstKind.sat_sub or node.kind == AstKind.sat_mul or node.kind == AstKind.sat_shl) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        if (node.kind == AstKind.sat_add) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SADD, .lhs = lhs, .rhs = rhs, .result = tid } });
        } else if (node.kind == AstKind.sat_sub) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SSUB, .lhs = lhs, .rhs = rhs, .result = tid } });
        } else if (node.kind == AstKind.sat_mul) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SMUL, .lhs = lhs, .rhs = rhs, .result = tid } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SSHL, .lhs = lhs, .rhs = rhs, .result = tid } });
        }
        return tid;
    } else if (node.kind == AstKind.div) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitSafeCheckDivMod(self, lhs, rhs);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_DIV, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.mod_op) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitSafeCheckDivMod(self, lhs, rhs);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MOD, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_and) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_or) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_OR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_xor) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XOR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.shl) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        lhs = materializeShiftLhs(self, node_idx, lhs, rtype);
        var tid = nextTemp(self, rtype);
        emitSafeCheckShift(self, lhs, rhs);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_SHL, lhs, rhs, getTempType(self, lhs));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHL, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.shr) {
        var res = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var rtype: u32 = if (res) |rt| rt else type_mod.TYPE_U32;
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = rtype;
            if (rtype == type_mod.TYPE_INT_LIT or rtype == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, rtype);
        emitSafeCheckShift(self, lhs, rhs);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHR, .lhs = lhs, .rhs = rhs, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.cmp_eq or node.kind == AstKind.cmp_ne) {
        var c0n = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        var c1n = ast_mod.astStoreNodeAt(self.ctx.store, node.child_1);
        var is_opt_null: u8 = @intCast(u8, 0);
        var opt_child: u32 = @intCast(u32, 0);
        if (c0n.kind == AstKind.null_literal and c1n.kind != AstKind.null_literal) {
            opt_child = node.child_1; is_opt_null = @intCast(u8, 1);
        } else if (c1n.kind == AstKind.null_literal and c0n.kind != AstKind.null_literal) {
            opt_child = node.child_0; is_opt_null = @intCast(u8, 1);
        }
        if (is_opt_null != @intCast(u8, 0)) {
            var opt_ty = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, opt_child);
            if (opt_ty) |ot| {
                if (self.ctx.registry.types_items[@intCast(usize, ot)].kind == type_mod.TypeKind.optional_type) {
                    var opt_val = lowerExpr(self, opt_child);
                    var has_val = nextTemp(self, type_mod.TYPE_U8);
                    emitInst(self, LirInst{ .check_optional = .{ .value = opt_val, .result = has_val } });
                    if (node.kind == AstKind.cmp_eq) {
                        var result = nextTemp(self, type_mod.TYPE_BOOL);
                        emitInst(self, LirInst{ .unary = .{ .op = UN_NOT, .operand = has_val, .result = result } });
                        return result;
                    } else {
                        return has_val;
                    }
                }
            }
        }
        var lhs = lowerExpr(self, node.child_0);
        var rhs = lowerExpr(self, node.child_1);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        if (node.kind == AstKind.cmp_eq) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_EQ, .lhs = lhs, .rhs = rhs, .result = tid } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_NE, .lhs = lhs, .rhs = rhs, .result = tid } });
        }
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
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = result, .src = rhs_tid } });
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
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = result, .src = rhs_tid } });
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
        var rt_ng = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ng_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_ng) |t| { if (t != type_mod.TYPE_UNDEFINED) { ng_box[0] = t; } } else { var rtm_ng: []const u8 = "RTMISS:n"; pal.markerWrite(rtm_ng); var rtmb_ng: [10]u8 = undefined; var rtml_ng = itoa_mod.itoa(node_idx, rtmb_ng[0..]); var rtms_ng: usize = @intCast(usize, 9) - @intCast(usize, rtml_ng); pal.markerWrite(rtmb_ng[rtms_ng..@intCast(usize, 9)]); var rtmnl_ng: []const u8 = "\n"; pal.markerWrite(rtmnl_ng); }
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = ng_box[0];
            if (ft == type_mod.TYPE_INT_LIT or ft == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, ng_box[0]);
        emitSafeCheckNegate(self, val, ng_box[0]);
        emitInst(self, LirInst{ .unary = .{ .op = UN_NEG, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.wrap_negate) {
        var rt_wn = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var wn_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_wn) |t| { if (t != type_mod.TYPE_UNDEFINED) { wn_box[0] = t; } }
        var wn_val = lowerExpr(self, node.child_0);
        var wn_tid = nextTemp(self, wn_box[0]);
        emitInst(self, LirInst{ .unary = .{ .op = UN_WNEG, .operand = wn_val, .result = wn_tid } });
        return wn_tid;
    } else if (node.kind == AstKind.bool_not) {
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, type_mod.TYPE_BOOL);
        emitInst(self, LirInst{ .unary = .{ .op = UN_NOT, .operand = val, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.bit_not) {
        var rt_bn = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var bn_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_bn) |t| { if (t != type_mod.TYPE_UNDEFINED) { bn_box[0] = t; } }
        if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
            var ft: u32 = bn_box[0];
            if (ft == type_mod.TYPE_INT_LIT or ft == type_mod.TYPE_UNDEFINED) { ft = type_mod.TYPE_I32; }
            var ctid = nextTemp(self, ft);
            emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = ctid } });
            return ctid;
        }
        var val = lowerExpr(self, node.child_0);
        var tid = nextTemp(self, bn_box[0]);
        emitInst(self, LirInst{ .unary = .{ .op = UN_BNOT, .operand = val, .result = tid } });
        return tid;
      } else if (node.kind == AstKind.plain_assign) {
         var child_node = ast_mod.astStoreNodeAt(store, node.child_0);
          var coe_m: []const u8 = "COE:k"; pal.markerWrite(coe_m);
          var co2_m: []const u8 = "CO2:p\n"; pal.markerWrite(co2_m);
         var coe_kb: [10]u8 = undefined; var coe_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(child_node.kind)), coe_kb[0..]); var coe_ks: usize = @intCast(usize, 9) - @intCast(usize, coe_kl); pal.markerWrite(coe_kb[coe_ks..@intCast(usize, 9)]);
         var coe_nm: []const u8 = "n"; pal.markerWrite(coe_nm);
         var coe_nb: [10]u8 = undefined; var coe_nl = itoa_mod.itoa(node_idx, coe_nb[0..]); var coe_ns: usize = @intCast(usize, 9) - @intCast(usize, coe_nl); pal.markerWrite(coe_nb[coe_ns..@intCast(usize, 9)]);
         var coe_nl2: []const u8 = "\n"; pal.markerWrite(coe_nl2);
          var src = lowerExpr(self, node.child_1);
          if (src == TEMP_NONE) {
              var rhs_node = ast_mod.astStoreNodeAt(store, node.child_1);
              var is_resolved: u8 = @intCast(u8, 0);
              if (rhs_node.kind == AstKind.ident_expr) {
                  var rhs_name = ast_mod.astStoreIdentifier(store, node.child_1);
                  if (findLocalTemp(self, rhs_name) != null) { is_resolved = @intCast(u8, 1); }
              }
              if (is_resolved == @intCast(u8, 0)) {
                  var vfpa0_m: []const u8 = "VFLOW:paS0\n"; pal.markerWrite(vfpa0_m);
                  return @intCast(u32, 0);
              }
          }
           if (src != TEMP_NONE and getTempType(self, src) == type_mod.TYPE_VOID) {
             var t4u_ds_m: []const u8 = "T4U:dS\n"; pal.markerWrite(t4u_ds_m);
         }
        lowerAssignLValue(self, node.child_0, src, node_idx);

        return src;
    } else if (node.kind == AstKind.deref) {
        var ptr_temp = lowerExpr(self, node.child_0);
        var rt_dr = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var dr_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_dr) |t| { if (t != type_mod.TYPE_UNDEFINED) { dr_box[0] = t; } } else { var rtm_dr: []const u8 = "RTMISS:n"; pal.markerWrite(rtm_dr); var rtmb_dr: [10]u8 = undefined; var rtml_dr = itoa_mod.itoa(node_idx, rtmb_dr[0..]); var rtms_dr: usize = @intCast(usize, 9) - @intCast(usize, rtml_dr); pal.markerWrite(rtmb_dr[rtms_dr..@intCast(usize, 9)]); var rtmnl_dr: []const u8 = "\n"; pal.markerWrite(rtmnl_dr); }
        if (dr_box[0] == type_mod.TYPE_VOID) { var vflow_drv: []const u8 = "VFLOW:drv\n"; pal.markerWrite(vflow_drv); }
        var tid = nextTemp(self, dr_box[0]);
        emitInst(self, LirInst{ .load = .{ .ptr = ptr_temp, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.address_of) {
        var rt_ao = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ao_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
        if (rt_ao) |t| { if (t != type_mod.TYPE_UNDEFINED) { ao_box[0] = t; } } else { var rtm_ao: []const u8 = "RTMISS:n"; pal.markerWrite(rtm_ao); var rtmb_ao: [10]u8 = undefined; var rtml_ao = itoa_mod.itoa(node_idx, rtmb_ao[0..]); var rtms_ao: usize = @intCast(usize, 9) - @intCast(usize, rtml_ao); pal.markerWrite(rtmb_ao[rtms_ao..@intCast(usize, 9)]); var rtmnl_ao: []const u8 = "\n"; pal.markerWrite(rtmnl_ao); }
        return lowerLValueAddr(self, node.child_0, ao_box[0]);
    } else if (node.kind == AstKind.index_access) {
        var base_temp = lowerExpr(self, node.child_0);
        var idxk: [1]u32 = [1]u32{@intCast(u32, 0)};
        var idxb = self.hoisted_temps.items[@intCast(usize, base_temp)].type_id;
        if (idxb != type_mod.TYPE_UNDEFINED) { var idxbt = self.ctx.registry.types_items[@intCast(usize, idxb)]; idxk[0] = @intCast(u32, @enumToInt(idxbt.kind)); }
        var idx_m: []const u8 = "IDX:b"; pal.markerWrite(idx_m);
        var idx_bb: [10]u8 = undefined; var idx_bl = itoa_mod.itoa(base_temp, idx_bb[0..]); var idx_bs: usize = @intCast(usize, 9) - @intCast(usize, idx_bl); pal.markerWrite(idx_bb[idx_bs..@intCast(usize, 9)]);
        var idx_km: []const u8 = "k"; pal.markerWrite(idx_km);
        var idx_kb: [10]u8 = undefined; var idx_kl = itoa_mod.itoa(idxk[0], idx_kb[0..]); var idx_ks: usize = @intCast(usize, 9) - @intCast(usize, idx_kl); pal.markerWrite(idx_kb[idx_ks..@intCast(usize, 9)]);
        var idx_nl: []const u8 = "\n"; pal.markerWrite(idx_nl);
        var msp_m: []const u8 = "MSP:b"; pal.markerWrite(msp_m);
        var msp_bb: [10]u8 = undefined; var msp_bl = itoa_mod.itoa(base_temp, msp_bb[0..]); var msp_bs: usize = @intCast(usize, 9) - @intCast(usize, msp_bl); pal.markerWrite(msp_bb[msp_bs..@intCast(usize, 9)]);
        var msp_nm: []const u8 = "n"; pal.markerWrite(msp_nm);
        var msp_nb: [10]u8 = undefined; var msp_nl = itoa_mod.itoa(node.child_0, msp_nb[0..]); var msp_ns: usize = @intCast(usize, 9) - @intCast(usize, msp_nl); pal.markerWrite(msp_nb[msp_ns..@intCast(usize, 9)]);
        var li_orig_base = base_temp;
        base_temp = maybeExtractSlicePtr(self, node.child_0, base_temp);
        var msp2_m: []const u8 = "p"; pal.markerWrite(msp2_m);
        var msp2b: [10]u8 = undefined; var msp2l = itoa_mod.itoa(base_temp, msp2b[0..]); var msp2s: usize = @intCast(usize, 9) - @intCast(usize, msp2l); pal.markerWrite(msp2b[msp2s..@intCast(usize, 9)]);
        var msp_nl2: []const u8 = "\n"; pal.markerWrite(msp_nl2);
        var idx_temp = lowerExpr(self, node.child_1);
        emitSafeCheckIndex(self, li_orig_base, node.child_0, idx_temp);
         var elem_type: [1]u32 = [1]u32{type_mod.TYPE_U32};
         var rt_ix = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
         if (rt_ix) |t| { if (t != type_mod.TYPE_UNDEFINED) { elem_type[0] = t; var ixh: []const u8 = "IXH"; pal.markerWrite(ixh); var ixhtb: [10]u8 = undefined; var ixhtl = itoa_mod.itoa(t, ixhtb[0..]); var ixhts: usize = @intCast(usize, 9) - @intCast(usize, ixhtl); pal.markerWrite(ixhtb[ixhts..@intCast(usize, 9)]); } }
         else {
         var ixm2: []const u8 = "IXM"; pal.markerWrite(ixm2);
         var reg = self.ctx.registry;
         var bt = self.hoisted_temps.items[@intCast(usize, base_temp)].type_id;
         if (bt != type_mod.TYPE_UNDEFINED) {
             var bty = reg.types_items[@intCast(usize, bt)];
             var ix_elem = type_mod.typeRegistryIndexedElemType(reg, bt);
             if (ix_elem != type_mod.TYPE_UNDEFINED) {
                 elem_type[0] = ix_elem;
             }
         }
         }
        var tid = nextTemp(self, elem_type[0]);
        var li_ni: u32 = @intCast(u32, 0);
        var src_ni = resolved_mod.resolvedSourceTableGet(self.ctx.resolved_types, node.child_0);
        if (src_ni) |sn| {
            li_ni = sn;
            var slr: []const u8 = "SLR:n"; pal.markerWrite(slr);
            var slr_b: [10]u8 = undefined; var slr_l = itoa_mod.itoa(sn, slr_b[0..]); var slr_s: usize = @intCast(usize, 9) - @intCast(usize, slr_l); pal.markerWrite(slr_b[slr_s..@intCast(usize, 9)]);
            var slr_nl: []const u8 = "\n"; pal.markerWrite(slr_nl);
        } else {
        if (ast_mod.astStoreNodeAt(store, node.child_0).kind == AstKind.ident_expr) {
            var c0_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
            var is_slice: u8 = @intCast(u8, 0);
            if (c0_rt) |t| { var c0_ty = self.ctx.registry.types_items[@intCast(usize, t)]; if (@enumToInt(c0_ty.kind) == @intCast(u32, @enumToInt(type_mod.TypeKind.slice_type))) { is_slice = @intCast(u8, 1); } }
            if (is_slice == @intCast(u8, 0)) { li_ni = ast_mod.astStoreIdentifier(store, node.child_0); }
        }
        }
        if (base_temp != li_orig_base) { li_ni = @intCast(u32, 0); }
        emitInst(self, LirInst{ .load_index = .{ .name_id = li_ni, .base = base_temp, .index = idx_temp, .result = tid } });
        var cli_m: []const u8 = "CLI:b"; pal.markerWrite(cli_m);
        var cli_bb: [10]u8 = undefined; var cli_bl = itoa_mod.itoa(base_temp, cli_bb[0..]); var cli_bs: usize = @intCast(usize, 9) - @intCast(usize, cli_bl); pal.markerWrite(cli_bb[cli_bs..@intCast(usize, 9)]);
        var cli_nm: []const u8 = "n"; pal.markerWrite(cli_nm);
        var cli_nb: [10]u8 = undefined; var cli_nl = itoa_mod.itoa(li_ni, cli_nb[0..]); var cli_ns: usize = @intCast(usize, 9) - @intCast(usize, cli_nl); pal.markerWrite(cli_nb[cli_ns..@intCast(usize, 9)]);
        var cli_nl2: []const u8 = "\n"; pal.markerWrite(cli_nl2);
        return tid;
    } else if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(store, node_idx);
        var shadow = hash_mod.u32ToU32MapGet(&self.capture_shadow, name_id);
        if (shadow) |syn| { if (captureShadowShouldRedirect(self, name_id, syn)) { name_id = syn; } }
        name_id = resolveLocalSrcName(self, name_id);
        if (self.ctx.has_symbols != @intCast(u8, 0)) {
         var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, name_id);
         if (sym) |s| {
               if (s.kind == sym_mod.SymbolKind.global) {
                   if ((@intCast(u16, s.flags) & @intCast(u16, 1)) == @intCast(u16, 0)) {
                      var decl_node = ast_mod.astStoreNodeAt(store, s.decl_node);
                      if (decl_node.child_1 != 0) {
                          var init_node = ast_mod.astStoreNodeAt(store, decl_node.child_1);
                           var literal_tid: u32 = @intCast(u32, 0);
                           if (init_node.kind == AstKind.int_literal) {
                              var val = ast_mod.astStoreIntValue(store, decl_node.child_1);
                              var tid = nextTemp(self, type_mod.TYPE_U32);
                              emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
                              literal_tid = tid;
                          }
                          if (init_node.kind == AstKind.float_literal) {
                              var val = store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(store, decl_node.child_1))];
                              var tid = nextTemp(self, type_mod.TYPE_F64);
                              emitInst(self, LirInst{ .float_const = .{ .value = val, .result = tid } });
                              literal_tid = tid;
                          }
                          if (init_node.kind == AstKind.char_literal) {
                              var val = ast_mod.astStoreIntValue(store, decl_node.child_1);
                              var tid = nextTemp(self, type_mod.TYPE_U8);
                              emitInst(self, LirInst{ .int_const = .{ .value = val, .result = tid } });
                              literal_tid = tid;
                          }
                           if (literal_tid != @intCast(u32, 0)) {
                                var s_ty = self.ctx.registry.types_items[@intCast(usize, s.type_id)];
                                var rt_tu2 = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
                                if (rt_tu2) |rt2v| { s_ty = self.ctx.registry.types_items[@intCast(usize, rt2v)]; }
                               var pik_m: []const u8 = "PIK:n"; pal.markerWrite(pik_m);
                               var pik_nb: [10]u8 = undefined; var pik_nl = itoa_mod.itoa(name_id, pik_nb[0..]); var pik_ns: usize = @intCast(usize, 9) - @intCast(usize, pik_nl); pal.markerWrite(pik_nb[pik_ns..@intCast(usize, 9)]);
                               var pik_km: []const u8 = "k"; pal.markerWrite(pik_km);
                               var pik_kb: [10]u8 = undefined; var pik_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(s_ty.kind)), pik_kb[0..]); var pik_ks: usize = @intCast(usize, 9) - @intCast(usize, pik_kl); pal.markerWrite(pik_kb[pik_ks..@intCast(usize, 9)]);
                               var pik_tm: []const u8 = "t"; pal.markerWrite(pik_tm);
                               var pik_tb: [10]u8 = undefined; var pik_tl = itoa_mod.itoa(s.type_id, pik_tb[0..]); var pik_ts: usize = @intCast(usize, 9) - @intCast(usize, pik_tl); pal.markerWrite(pik_tb[pik_ts..@intCast(usize, 9)]);
                               var pik_nl2: []const u8 = "\n"; pal.markerWrite(pik_nl2);
                                var tuc_sk = @intCast(u32, @enumToInt(s_ty.kind));
                                var tuc_m: []const u8 = "TUC:n"; pal.markerWrite(tuc_m);
                                var tuc_nb: [10]u8 = undefined; var tuc_nl = itoa_mod.itoa(name_id, tuc_nb[0..]); var tuc_ns: usize = @intCast(usize, 9) - @intCast(usize, tuc_nl); pal.markerWrite(tuc_nb[tuc_ns..@intCast(usize, 9)]);
                                var tuc_tm: []const u8 = "t"; pal.markerWrite(tuc_tm);
                                var tuc_tb: [10]u8 = undefined; var tuc_tl = itoa_mod.itoa(s.type_id, tuc_tb[0..]); var tuc_ts: usize = @intCast(usize, 9) - @intCast(usize, tuc_tl); pal.markerWrite(tuc_tb[tuc_ts..@intCast(usize, 9)]);
                                var tuc_km: []const u8 = "k"; pal.markerWrite(tuc_km);
                                var tuc_kb: [10]u8 = undefined; var tuc_kl = itoa_mod.itoa(tuc_sk, tuc_kb[0..]); var tuc_ks: usize = @intCast(usize, 9) - @intCast(usize, tuc_kl); pal.markerWrite(tuc_kb[tuc_ks..@intCast(usize, 9)]);
                                var tuc_vm: []const u8 = "v"; pal.markerWrite(tuc_vm);
                                var tuc_vb: [10]u8 = undefined; var tuc_vl = itoa_mod.itoa(literal_tid, tuc_vb[0..]); var tuc_vs: usize = @intCast(usize, 9) - @intCast(usize, tuc_vl); pal.markerWrite(tuc_vb[tuc_vs..@intCast(usize, 9)]);
                                var tuc_nl3: []const u8 = "\n"; pal.markerWrite(tuc_nl3);
                                if (s_ty.kind == type_mod.TypeKind.tagged_union_type) {
                                    var tutid_type: u32 = s.type_id;
                                    if (rt_tu2) |rt2v| { tutid_type = rt2v; }
                                    var tu_tid = nextTemp(self, tutid_type);
                                    emitInst(self, LirInst{ .assign_field = .{ .name_id = @intCast(u32, 0), .base = tu_tid, .field_id = type_mod.TU_FIELD_TAG, .src = literal_tid } });
                                  return tu_tid;
                              }
                              return literal_tid;
                          }
                     }
                    }
                      var gdb_here: []const u8 = "GDB_HERE_SYM"; pal.markerWrite(gdb_here);
                      var gtdb: [20]u8 = undefined; var gtdl = itoa_mod.itoa(s.type_id, gtdb[0..]); var gtds: usize = @intCast(usize, 19) - @intCast(usize, gtdl); pal.markerWrite(gtdb[gtds..@intCast(usize, 19)]);
                      var gkk: u32 = s.kind;
                      var gkdb: [20]u8 = undefined; var gkdl = itoa_mod.itoa(gkk, gkdb[0..]); var gkds: usize = @intCast(usize, 19) - @intCast(usize, gkdl); pal.markerWrite(gkdb[gkds..@intCast(usize, 19)]);
                      var gdn: []const u8 = "d"; pal.markerWrite(gdn);
                      var gddb: [20]u8 = undefined; var gddl = itoa_mod.itoa(s.decl_node, gddb[0..]); var gdds: usize = @intCast(usize, 19) - @intCast(usize, gddl); pal.markerWrite(gddb[gdds..@intCast(usize, 19)]);
                      var gnn: []const u8 = "n"; pal.markerWrite(gnn);
                      var gndb: [20]u8 = undefined; var gndl = itoa_mod.itoa(s.name_id, gndb[0..]); var gnds: usize = @intCast(usize, 19) - @intCast(usize, gndl); pal.markerWrite(gndb[gnds..@intCast(usize, 19)]);
                      var gnl2: []const u8 = "\n"; pal.markerWrite(gnl2);
                      var skip_rt: u32 = s.type_id;
                      if (skip_rt != @intCast(u32, 0)) {
                         var srty = self.ctx.registry.types_items[@intCast(usize, skip_rt)];
                         if (srty.kind == type_mod.TypeKind.fn_type or srty.kind == type_mod.TypeKind.module_type) {
                              return TEMP_NONE;
                         }
                     }
                     if (s.decl_node != 0) {
                         var dn_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, s.decl_node);
                         var b2m: []const u8 = "B2:dn"; pal.markerWrite(b2m);
                         var b2db: [20]u8 = undefined; var b2dl = itoa_mod.itoa(s.decl_node, b2db[0..]); var b2ds: usize = @intCast(usize, 19) - @intCast(usize, b2dl); pal.markerWrite(b2db[b2ds..@intCast(usize, 19)]);
                         if (dn_type) |dt| {
                             var b2hm: []const u8 = "H"; pal.markerWrite(b2hm);
                             var dty = self.ctx.registry.types_items[@intCast(usize, dt)];
                             var b2kb: [20]u8 = undefined; var b2kl = itoa_mod.itoa(@intCast(u32, @enumToInt(dty.kind)), b2kb[0..]); var b2ks: usize = @intCast(usize, 19) - @intCast(usize, b2kl); pal.markerWrite(b2kb[b2ks..@intCast(usize, 19)]);
                             if (dty.kind == type_mod.TypeKind.fn_type or dty.kind == type_mod.TypeKind.module_type) {
                                  return TEMP_NONE;
                             }
                         } else {
                             var b2mm: []const u8 = "M"; pal.markerWrite(b2mm);
                         }
                         var b2nl: []const u8 = "\n"; pal.markerWrite(b2nl);
                     }
                      return lowerGlobalRef(self, s.*, name_id);
                } else if (s.kind == sym_mod.SymbolKind.module) {
                    var mam: []const u8 = "module used as value expression";
                    _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 1), @intCast(u16, @enumToInt(diag_mod.ErrorCode.WARN_3023_MODULE_AS_VALUE)),
                        @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), mam);
                    return TEMP_NONE;
                } else if (s.kind == sym_mod.SymbolKind.function) {
                    var s_t: u32 = s.type_id;
                    if (s_t != @intCast(u32, 0)) {
                        type_mod.typeRegistryMarkFnPtrUsed(self.ctx.registry, s_t);
                        var fr_pt2 = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, s_t, false);
                        var fr_nid = s.name_id;
                        var fr_mid = self.module_id;
                        if (s.module_id != @intCast(u32, 0)) { fr_mid = s.module_id; }
                        var fr_res2 = nextTemp(self, fr_pt2);
                        emitInst(self, LirInst{ .func_ref = .{ .name_id = fr_nid, .module_id = fr_mid, .result = fr_res2 } });
                        return fr_res2;
                    }
                    return TEMP_NONE;
                } else if (s.kind == sym_mod.SymbolKind.local or s.kind == sym_mod.SymbolKind.param) {
                    if (findLocalTemp(self, name_id)) |fnd| {
                        return fnd;
                    }
                    return TEMP_NONE;
                } else if (s.kind == sym_mod.SymbolKind.type_alias) {
                    var atemp = nextTemp(self, s.type_id);
                    return atemp;
                }
         }
        }
        var ptype: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        var arr_temp: u32 = TEMP_NONE;
        var loc_binding = resolveLocal(self, name_id);
        if (loc_binding) |lb| { arr_temp = lb.temp; }

        var fnd_m: []const u8 = "FND:n"; pal.markerWrite(fnd_m);
        var fnd_nb: [10]u8 = undefined; var fnd_nl = itoa_mod.itoa(name_id, fnd_nb[0..]); var fnd_ns: usize = @intCast(usize, 9) - @intCast(usize, fnd_nl); pal.markerWrite(fnd_nb[fnd_ns..@intCast(usize, 9)]);
        var fnd_rm: []const u8 = "r"; pal.markerWrite(fnd_rm);
        var fnd_rb: [10]u8 = undefined; var fnd_rl = itoa_mod.itoa(arr_temp, fnd_rb[0..]); var fnd_rs: usize = @intCast(usize, 9) - @intCast(usize, fnd_rl); pal.markerWrite(fnd_rb[fnd_rs..@intCast(usize, 9)]);
        var fnd_nl2: []const u8 = "\n"; pal.markerWrite(fnd_nl2);
        var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var lrb_m: []const u8 = "LRB:n"; pal.markerWrite(lrb_m);
        var lrb_nb: [10]u8 = undefined; var lrb_nl = itoa_mod.itoa(node_idx, lrb_nb[0..]); var lrb_ns: usize = @intCast(usize, 9) - @intCast(usize, lrb_nl); pal.markerWrite(lrb_nb[lrb_ns..@intCast(usize, 9)]);
        if (rt) |t| { var lrb_tm: []const u8 = "T"; pal.markerWrite(lrb_tm); var lrb_tb: [10]u8 = undefined; var lrb_tl = itoa_mod.itoa(t, lrb_tb[0..]); var lrb_ts: usize = @intCast(usize, 9) - @intCast(usize, lrb_tl); pal.markerWrite(lrb_tb[lrb_ts..@intCast(usize, 9)]); var vfrth_m: []const u8 = "VFLOW:irH\n"; pal.markerWrite(vfrth_m); } else { var lrb_xm: []const u8 = "X"; pal.markerWrite(lrb_xm); var vfrtm_m: []const u8 = "VFLOW:irM\n"; pal.markerWrite(vfrtm_m); }
        var lrb_nl2: []const u8 = "\n"; pal.markerWrite(lrb_nl2);
        if (rt) |t| {
            if (t != type_mod.TYPE_UNDEFINED) {
                var rty = self.ctx.registry.types_items[@intCast(usize, t)];
                if (rty.kind == type_mod.TypeKind.fn_type or rty.kind == type_mod.TypeKind.module_type) {
                    return TEMP_NONE;
                }
                ptype = t;
            }
        }
        if (ptype == type_mod.TYPE_UNDEFINED) {
            var vfu_m: []const u8 = "VFLOW:iFU\n"; pal.markerWrite(vfu_m);
            var fu: []const u8 = "F3cU:n"; pal.markerWrite(fu);
            var fub: [20]u8 = undefined; var ful = itoa_mod.itoa(name_id, fub[0..]); var fus: usize = @intCast(usize, 19) - @intCast(usize, ful); pal.markerWrite(fub[fus..@intCast(usize, 19)]);
            var fus2: []const u8 = "s"; pal.markerWrite(fus2);
            var fsn = si_mod.stringInternerGet(self.ctx.registry.interner, name_id);
            pal.markerWrite(fsn);
            var funl2: []const u8 = " "; pal.markerWrite(funl2);
            ptype = type_mod.TYPE_U32;
        }
        var arr_kind: u8 = @intCast(u8, 0);
        var arr_tid: u32 = @intCast(u32, 0);
        if (loc_binding) |lb| {
            arr_kind = lb.kind;
            arr_tid = lb.tid;
        }
        if (arr_tid == type_mod.TYPE_VOID) { var vflb_m: []const u8 = "VFLOW:iTV\n"; pal.markerWrite(vflb_m); }

         var a3r_m: []const u8 = "A3R:r"; pal.markerWrite(a3r_m);
         var a3r_rb: [10]u8 = undefined; var a3r_rl = itoa_mod.itoa(arr_temp, a3r_rb[0..]); var a3r_rs: usize = @intCast(usize, 9) - @intCast(usize, a3r_rl); pal.markerWrite(a3r_rb[a3r_rs..@intCast(usize, 9)]);
         var a3r_km: []const u8 = "k"; pal.markerWrite(a3r_km);
         var a3r_kb: [10]u8 = undefined; var a3r_kl = itoa_mod.itoa(@intCast(u32, arr_kind), a3r_kb[0..]); var a3r_ks: usize = @intCast(usize, 9) - @intCast(usize, a3r_kl); pal.markerWrite(a3r_kb[a3r_ks..@intCast(usize, 9)]);
         var a3r_tm: []const u8 = "t"; pal.markerWrite(a3r_tm);
         var a3r_tb: [10]u8 = undefined; var a3r_tl = itoa_mod.itoa(arr_tid, a3r_tb[0..]); var a3r_ts: usize = @intCast(usize, 9) - @intCast(usize, a3r_tl); pal.markerWrite(a3r_tb[a3r_ts..@intCast(usize, 9)]);
         var a3r_nl: []const u8 = "\n"; pal.markerWrite(a3r_nl);
        var parm_m: []const u8 = "PARM:n"; pal.markerWrite(parm_m);
        var parm_nb: [10]u8 = undefined; var parm_nl = itoa_mod.itoa(name_id, parm_nb[0..]); var parm_ns: usize = @intCast(usize, 9) - @intCast(usize, parm_nl); pal.markerWrite(parm_nb[parm_ns..@intCast(usize, 9)]);
        var parm_tm: []const u8 = "t"; pal.markerWrite(parm_tm);
        var parm_tb: [10]u8 = undefined; var parm_tl = itoa_mod.itoa(ptype, parm_tb[0..]); var parm_ts: usize = @intCast(usize, 9) - @intCast(usize, parm_tl); pal.markerWrite(parm_tb[parm_ts..@intCast(usize, 9)]);
        var parm_am: []const u8 = "a"; pal.markerWrite(parm_am);
        var parm_ab: [10]u8 = undefined; var parm_al = itoa_mod.itoa(arr_temp, parm_ab[0..]); var parm_as2: usize = @intCast(usize, 9) - @intCast(usize, parm_al); pal.markerWrite(parm_ab[parm_as2..@intCast(usize, 9)]);
        var parm_km: []const u8 = "k"; pal.markerWrite(parm_km);
        var parm_kb: [10]u8 = undefined; var parm_kl = itoa_mod.itoa(@intCast(u32, arr_kind), parm_kb[0..]); var parm_ks: usize = @intCast(usize, 9) - @intCast(usize, parm_kl); pal.markerWrite(parm_kb[parm_ks..@intCast(usize, 9)]);
        var parm_nl2: []const u8 = "\n"; pal.markerWrite(parm_nl2);
        if (arr_tid == type_mod.TYPE_VOID) {
            var vfvx_m: []const u8 = "VFIX:iVX\n"; pal.markerWrite(vfvx_m);
            return @intCast(u32, 0);
        }
        if (arr_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.array_type))) { _ = hash_mod.u32ToU32MapPut(&self.local_decl_name_map, arr_temp, name_id); return arr_temp; }
        if (arr_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.slice_type))) { _ = hash_mod.u32ToU32MapPut(&self.local_decl_name_map, arr_temp, name_id); return arr_temp; }
        if (arr_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.tagged_union_type))) { _ = hash_mod.u32ToU32MapPut(&self.local_decl_name_map, arr_temp, name_id); return arr_temp; }
        if (arr_kind == @intCast(u8, @enumToInt(type_mod.TypeKind.struct_type))) { _ = hash_mod.u32ToU32MapPut(&self.local_decl_name_map, arr_temp, name_id); return arr_temp; }
        if (arr_kind != @intCast(u8, 0) and ptype != type_mod.TYPE_UNDEFINED) { if (arr_tid == type_mod.TYPE_VOID) { var vfrv_m: []const u8 = "VFLOW:iRV\n"; pal.markerWrite(vfrv_m); } _ = hash_mod.u32ToU32MapPut(&self.local_decl_name_map, arr_temp, name_id); return arr_temp; }
        if (arr_kind != @intCast(u8, 0)) {
            var tpp_m: []const u8 = "TPP:a"; pal.markerWrite(tpp_m);
            var tpp_ab: [10]u8 = undefined; var tpp_al = itoa_mod.itoa(arr_temp, tpp_ab[0..]); var tpp_as: usize = @intCast(usize, 9) - @intCast(usize, tpp_al); pal.markerWrite(tpp_ab[tpp_as..@intCast(usize, 9)]);
            var tpp_km: []const u8 = "k"; pal.markerWrite(tpp_km);
            var tpp_kb: [10]u8 = undefined; var tpp_kl = itoa_mod.itoa(@intCast(u32, arr_kind), tpp_kb[0..]); var tpp_ks: usize = @intCast(usize, 9) - @intCast(usize, tpp_kl); pal.markerWrite(tpp_kb[tpp_ks..@intCast(usize, 9)]);
            var tpp_tm: []const u8 = "t"; pal.markerWrite(tpp_tm);
            var tpp_tb: [10]u8 = undefined; var tpp_tl = itoa_mod.itoa(arr_tid, tpp_tb[0..]); var tpp_ts: usize = @intCast(usize, 9) - @intCast(usize, tpp_tl); pal.markerWrite(tpp_tb[tpp_ts..@intCast(usize, 9)]);
            if (rt) |rtt| {
                self.hoisted_temps.items[@intCast(usize, arr_temp)].type_id = rtt;
                var hot_m: []const u8 = "HOT:a"; pal.markerWrite(hot_m);
                var hot_ab: [10]u8 = undefined; var hot_al = itoa_mod.itoa(arr_temp, hot_ab[0..]); var hot_as: usize = @intCast(usize, 9) - @intCast(usize, hot_al); pal.markerWrite(hot_ab[hot_as..@intCast(usize, 9)]);
                var hot_tm: []const u8 = "t"; pal.markerWrite(hot_tm);
                var hot_tb: [10]u8 = undefined; var hot_tl = itoa_mod.itoa(rtt, hot_tb[0..]); var hot_ts: usize = @intCast(usize, 9) - @intCast(usize, hot_tl); pal.markerWrite(hot_tb[hot_ts..@intCast(usize, 9)]);
                var hot_nl: []const u8 = "\n"; pal.markerWrite(hot_nl);
            } else {
                var hot_m2: []const u8 = "HOT:a"; pal.markerWrite(hot_m2);
                var hot_ab2: [10]u8 = undefined; var hot_al2 = itoa_mod.itoa(arr_temp, hot_ab2[0..]); var hot_as2: usize = @intCast(usize, 9) - @intCast(usize, hot_al2); pal.markerWrite(hot_ab2[hot_as2..@intCast(usize, 9)]);
                if (arr_tid != type_mod.TYPE_UNDEFINED) { self.hoisted_temps.items[@intCast(usize, arr_temp)].type_id = arr_tid; var hot_tm2: []const u8 = "tP\n"; pal.markerWrite(hot_tm2); } else { var hot_tm2: []const u8 = "tMISS\n"; pal.markerWrite(hot_tm2); }
            }
        }
        if (arr_kind != @intCast(u8, 0)) {
            var load_ty = ptype;

            var tid = nextTemp(self, load_ty);
            var ncb_m: []const u8 = "NCB:t"; pal.markerWrite(ncb_m);
            var ncb_tb: [10]u8 = undefined; var ncb_tl = itoa_mod.itoa(tid, ncb_tb[0..]); var ncb_ts: usize = @intCast(usize, 9) - @intCast(usize, ncb_tl); pal.markerWrite(ncb_tb[ncb_ts..@intCast(usize, 9)]);
            var ncb_ym: []const u8 = "Y"; pal.markerWrite(ncb_ym);
            var ncb_yb: [10]u8 = undefined; var ncb_yl = itoa_mod.itoa(ptype, ncb_yb[0..]); var ncb_ys: usize = @intCast(usize, 9) - @intCast(usize, ncb_yl); pal.markerWrite(ncb_yb[ncb_ys..@intCast(usize, 9)]);
            var ncb_nl: []const u8 = "\n"; pal.markerWrite(ncb_nl);
            emitInst(self, LirInst{ .load_local = .{ .name_id = name_id, .result = tid } });
            return tid;
        }
        var tid = nextTemp(self, ptype);
        emitInst(self, LirInst{ .load_local = .{ .name_id = name_id, .result = tid } });
        return tid;
    } else if (node.kind == AstKind.field_access) {
        var field_name_id: u32 = ast_mod.astStoreNodePayload(store, node_idx);
        var base_node = ast_mod.astStoreNodeAt(store, node.child_0);
        if (base_node.kind == AstKind.field_access) {
            var npl_tid = lowerTryNestedPackedLeafRead(self, node_idx);
            if (npl_tid != TEMP_NONE) return npl_tid;
        }
        if (base_node.kind == AstKind.ident_expr and self.ctx.has_symbols != @intCast(u8, 0)) {
            var base_name_id = ast_mod.astStoreIdentifier(store, node.child_0);
            var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, base_name_id);
            if (sym) |s| {
                if (s.kind == sym_mod.SymbolKind.type_alias) {
                    var key: u64 = @intCast(u64, self.module_id) * @intCast(u64, 4294967296) + @intCast(u64, base_name_id);
                    var lt = type_mod.nameCacheGet(self.ctx.registry, key);
                    if (lt) |type_id| {
                        var f3s: []const u8 = "F3:1\n"; pal.markerWrite(f3s);
                        var ty = self.ctx.registry.types_items[@intCast(usize, type_id)];
                        if (ty.kind == type_mod.TypeKind.tagged_union_type) {
                            var tp = self.ctx.registry.tu_items[@intCast(usize, ty.payload_idx)];
                            var fstart: usize = @intCast(usize, tp.fields_start);
                            var fcount: usize = @intCast(usize, tp.fields_count);
                            var fi: usize = 0;
                            while (fi < fcount) : (fi += 1) {
                                if (self.ctx.registry.fe_items[fstart + fi].name_id == field_name_id) {
                                    var ft_box: [1]u32 = [1]u32{tp.tag_type};
                                     var ftrt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
                                     var eff_type: [1]u32 = [1]u32{type_id};
                                     if (ftrt) |t2| { if (t2 != type_mod.TYPE_UNDEFINED and t2 != type_mod.TYPE_VOID) { eff_type[0] = t2; } }
                                     return emitTaggedUnionInit(self, eff_type[0], @intCast(u32, fi));
                                }
                            }
                        }
                        if (ty.kind == type_mod.TypeKind.enum_type) {
                            var ep = self.ctx.registry.en_items[@intCast(usize, ty.payload_idx)];
                            var estart: usize = @intCast(usize, ep.members_start);
                            var ecount: usize = @intCast(usize, ep.members_count);
                            var ei: usize = 0;
                            while (ei < ecount) : (ei += 1) {
                                var member = self.ctx.registry.em_items[estart + ei];
                                if (member.name_id == field_name_id) {
                                    var eftid = nextTemp(self, type_id);
                                    emitInst(self, LirInst{ .enum_const = .{ .value = @bitCast(u64, member.value), .result = eftid, .type_id = type_id, .member_name_id = member.name_id } });
                                    var enl_m: []const u8 = "ENLF:t"; pal.markerWrite(enl_m);
                                    var enl_tb: [10]u8 = undefined; var enl_tl = itoa_mod.itoa(type_id, enl_tb[0..]); var enl_ts: usize = @intCast(usize, 9) - @intCast(usize, enl_tl); pal.markerWrite(enl_tb[enl_ts..@intCast(usize, 9)]);
                                    var enl_cm: []const u8 = "c"; pal.markerWrite(enl_cm);
                                    var enl_cb: [24]u8 = undefined; var enl_cl = itoa_mod.itoa64(@bitCast(u64, member.value), enl_cb[0..]); var enl_cs: usize = @intCast(usize, 23) - @intCast(usize, enl_cl); pal.markerWrite(enl_cb[enl_cs..@intCast(usize, 23)]);
                                    var enl_nl: []const u8 = "\n"; pal.markerWrite(enl_nl);
                                    return eftid;
                                }
                            }
                        }
                         if (ty.kind == type_mod.TypeKind.error_set_type) {
                            var ordinal = type_mod.typeRegistryErrorSetMemberIndex(self.ctx.registry, type_id, field_name_id);
                            if (ordinal != @intCast(u32, 0xFFFFFFFF)) {
                                var reg_code = hash_mod.u32ToU32MapGetOrAddDense(self.ctx.error_code_registry, field_name_id);
                                var eftid = nextTemp(self, type_id);
                                emitInst(self, LirInst{ .enum_const = .{
                                    .value = @intCast(u64, reg_code),
                                    .result = eftid,
                                    .type_id = type_id,
                                    .member_name_id = field_name_id,
                                }});
                                return eftid;
                            }
                        }
                    }
                }
                if (s.kind == sym_mod.SymbolKind.module) {
                    var target_mod = s.module_id;
                    var res_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, target_mod, field_name_id);
                    if (res_sym) |ts| {
                        if (ts.kind == sym_mod.SymbolKind.type_alias) {
                            var res_type_id = ts.type_id;
                            if (res_type_id != @intCast(u32, 0)) {
                                var gtemp = nextTemp(self, res_type_id);
                                return gtemp;
                            }
                        } else if (ts.kind == sym_mod.SymbolKind.function) {
                            var fn_type_id = ts.type_id;
                            if (fn_type_id != @intCast(u32, 0)) {
                                type_mod.typeRegistryMarkFnPtrUsed(self.ctx.registry, fn_type_id);
                                var fr_pt = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, fn_type_id, false);
                                var fr_res = nextTemp(self, fr_pt);
                                emitInst(self, LirInst{ .func_ref = .{ .name_id = ts.name_id, .module_id = target_mod, .result = fr_res } });
                                return fr_res;
                            }
                        } else if (ts.kind == sym_mod.SymbolKind.global) {
                            var gbl_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, ts.decl_node);
                            var gbl_tid = if (gbl_type) |gt| gt else type_mod.TYPE_UNDEFINED;
                            if ((@intCast(u16, ts.flags) & @intCast(u16, 1)) == @intCast(u16, 0)) {
                                var gd_node = ast_mod.astStoreNodeAt(store, ts.decl_node);
                                if (gd_node.child_1 != 0) {
                                    var gi_node = ast_mod.astStoreNodeAt(store, gd_node.child_1);
                                    if (gi_node.kind == AstKind.int_literal or gi_node.kind == AstKind.char_literal) {
                                        var gval = ast_mod.astStoreIntValue(store, gd_node.child_1);
                                        var gtid = nextTemp(self, gbl_tid);
                                        emitInst(self, LirInst{ .int_const = .{ .value = gval, .result = gtid } });
                                        return gtid;
                                    }
                                    if (gi_node.kind == AstKind.float_literal) {
                                        var gval = store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(store, gd_node.child_1))];
                                        var gtid = nextTemp(self, gbl_tid);
                                        emitInst(self, LirInst{ .float_const = .{ .value = gval, .result = gtid } });
                                        return gtid;
                                    }
                                }
                            }
                            var gtemp = nextTemp(self, gbl_tid);
                            emitInst(self, LirInst{ .load_global = .{ .name_id = ts.name_id, .module_id = target_mod, .result = gtemp } });
                            return gtemp;
                        }
                    }
                }
            }
        }
        var base_temp = lowerExpr(self, node.child_0);
        if (base_temp == TEMP_NONE or base_temp >= @intCast(u32, self.hoisted_temps.len)) {

            var np_msg: []const u8 = "non-value base expression in field access";
            _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3042),
                @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), np_msg);
            var dummy = nextTemp(self, type_mod.TYPE_VOID);
            return dummy;

        }
        var base_ty = self.hoisted_temps.items[@intCast(usize, base_temp)].type_id;
        if (base_ty != type_mod.TYPE_UNDEFINED) {
            var bty = self.ctx.registry.types_items[@intCast(usize, base_ty)];
            if (bty.kind == type_mod.TypeKind.error_set_type) {
                var es_ordinal = type_mod.typeRegistryErrorSetMemberIndex(self.ctx.registry, base_ty, field_name_id);
                if (es_ordinal != @intCast(u32, 0xFFFFFFFF)) {
                    var reg_code = hash_mod.u32ToU32MapGetOrAddDense(self.ctx.error_code_registry, field_name_id);
                    var eftid2 = nextTemp(self, base_ty);
                    emitInst(self, LirInst{ .enum_const = .{
                        .value = @intCast(u64, reg_code),
                        .result = eftid2,
                        .type_id = base_ty,
                        .member_name_id = field_name_id,
                    }});
                    return eftid2;
                }
            }
        }
        var gape_fac: []const u8 = "GAPE:fac\n"; pal.markerWrite(gape_fac);
        var fabs_m: []const u8 = "FABS:bt"; pal.markerWrite(fabs_m);
        var fabs_b: [10]u8 = undefined; var fabs_tl = itoa_mod.itoa(self.hoisted_temps.items[@intCast(usize, base_temp)].type_id, fabs_b[0..]); var fabs_ts: usize = @intCast(usize, 9) - @intCast(usize, fabs_tl); pal.markerWrite(fabs_b[fabs_ts..@intCast(usize, 9)]);
        var fabs_nl: []const u8 = "\n"; pal.markerWrite(fabs_nl);
        var resolved_base = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (resolved_base) |_| { var f4s: []const u8 = "F4:H\n"; pal.markerWrite(f4s); } else { var f4m_f: []const u8 = "F4:Mf"; pal.markerWrite(f4m_f); var f4m_fb: [10]u8 = undefined; var f4m_fl = itoa_mod.itoa(node_idx, f4m_fb[0..]); var f4m_fs: usize = @intCast(usize, 9) - @intCast(usize, f4m_fl); pal.markerWrite(f4m_fb[f4m_fs..@intCast(usize, 9)]); var f4m_bm: []const u8 = "b"; pal.markerWrite(f4m_bm); var f4m_bb: [10]u8 = undefined; var f4m_bl = itoa_mod.itoa(node.child_0, f4m_bb[0..]); var f4m_bs: usize = @intCast(usize, 9) - @intCast(usize, f4m_bl); pal.markerWrite(f4m_bb[f4m_bs..@intCast(usize, 9)]); var f4mnl2: []const u8 = "\n"; pal.markerWrite(f4mnl2); }
        var rt_fa = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var fa_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        if (rt_fa) |t| { if (t != type_mod.TYPE_UNDEFINED) { fa_box[0] = t; } } else { var rtm_fa: []const u8 = "RTMISS:n"; pal.markerWrite(rtm_fa); var rtmb_fa: [10]u8 = undefined; var rtml_fa = itoa_mod.itoa(node_idx, rtmb_fa[0..]); var rtms_fa: usize = @intCast(usize, 9) - @intCast(usize, rtml_fa); pal.markerWrite(rtmb_fa[rtms_fa..@intCast(usize, 9)]); var rtmnl_fa: []const u8 = "\n"; pal.markerWrite(rtmnl_fa); }
        if (fa_box[0] == type_mod.TYPE_VOID) { var gape_fav: []const u8 = "GAPE:fav\n"; pal.markerWrite(gape_fav); }
        var d1f: []const u8 = "D1:FADr"; pal.markerWrite(d1f);
        var d1fb: [20]u8 = undefined;
        if (rt_fa) |d1t| { var d1fl = itoa_mod.itoa(d1t, d1fb[0..]); var d1fs: usize = @intCast(usize, 19) - @intCast(usize, d1fl); pal.markerWrite(d1fb[d1fs..@intCast(usize, 19)]); }
        else { var d1z: []const u8 = "NULL"; pal.markerWrite(d1z); }
        var d1fn: []const u8 = "fn"; pal.markerWrite(d1fn);
        var d1fnb: [20]u8 = undefined; var d1fnl = itoa_mod.itoa(field_name_id, d1fnb[0..]); var d1fns: usize = @intCast(usize, 19) - @intCast(usize, d1fnl); pal.markerWrite(d1fnb[d1fns..@intCast(usize, 19)]);
        var d1nl: []const u8 = " "; pal.markerWrite(d1nl);
        var fa_ty = self.ctx.registry.types_items[@intCast(usize, fa_box[0])];
        if (fa_ty.kind == type_mod.TypeKind.fn_type) {
            if (base_node.kind == AstKind.ident_expr and self.ctx.has_symbols != @intCast(u8, 0)) {
                var fr_base_name = ast_mod.astStoreIdentifier(store, node.child_0);
                var fr_base_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, fr_base_name);
                if (fr_base_sym) |frbsym| {
                    if (frbsym.module_id != @intCast(u32, 0) and frbsym.module_id != self.module_id) {
                        var fr_tmod = frbsym.module_id;
                        var fr_fsym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, fr_tmod, field_name_id);
                        if (fr_fsym) |frfsym| {
                            if (frfsym.kind == @intCast(u8, 3)) {
                                type_mod.typeRegistryMarkFnPtrUsed(self.ctx.registry, fa_box[0]);
                                var fr_pt = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, fa_box[0], false);
                                var fr_res = nextTemp(self, fr_pt);
                                emitInst(self, LirInst{ .func_ref = .{ .name_id = frfsym.name_id, .module_id = fr_tmod, .result = fr_res } });
                                var frm_m: []const u8 = "FREF:n"; pal.markerWrite(frm_m);
                                var frm_b: [10]u8 = undefined; var frm_l = itoa_mod.itoa(frfsym.name_id, frm_b[0..]); var frm_s: usize = @intCast(usize, 9) - @intCast(usize, frm_l); pal.markerWrite(frm_b[frm_s..@intCast(usize, 9)]);
                                var frm_nl: []const u8 = "\n"; pal.markerWrite(frm_nl);
                                return fr_res;
                            }
                        }
                    }
                }
            }
            return @intCast(u32, 0);
        }
        if (fa_ty.kind == type_mod.TypeKind.module_type) {
            return @intCast(u32, 0);
        }
        var fas_m: []const u8 = "FAS:n"; pal.markerWrite(fas_m);
        var fas_b: [20]u8 = undefined; var fas_l = itoa_mod.itoa(field_name_id, fas_b[0..]); var fas_s: usize = @intCast(usize, 19) - @intCast(usize, fas_l); pal.markerWrite(fas_b[fas_s..@intCast(usize, 19)]);
        var fas_tn: []const u8 = "t"; pal.markerWrite(fas_tn);
        var fas_tb: [20]u8 = undefined; var fas_tl = itoa_mod.itoa(fa_box[0], fas_tb[0..]); var fas_ts: usize = @intCast(usize, 19) - @intCast(usize, fas_tl); pal.markerWrite(fas_tb[fas_ts..@intCast(usize, 19)]);
        var fas_nl: []const u8 = " "; pal.markerWrite(fas_nl);
        var tid = nextTemp(self, fa_box[0]);
        if (resolved_base) |type_id| {
            var ty = self.ctx.registry.types_items[@intCast(usize, type_id)];
            var kind = ty.kind;
            var type_box: [1]u32 = [1]u32{type_id};
            if (kind == type_mod.TypeKind.ptr_type or kind == type_mod.TypeKind.many_ptr_type) {
                type_box[0] = self.ctx.registry.ptr_items[@intCast(usize, ty.payload_idx)].base;
                ty = self.ctx.registry.types_items[@intCast(usize, type_box[0])];
                kind = ty.kind;
                var fad2_m: []const u8 = "FAD2:k"; pal.markerWrite(fad2_m);
                var fad2_kb: [10]u8 = undefined; var fad2_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(kind)), fad2_kb[0..]); var fad2_ks: usize = @intCast(usize, 9) - @intCast(usize, fad2_kl); pal.markerWrite(fad2_kb[fad2_ks..@intCast(usize, 9)]);
                var fad2_nl: []const u8 = "\n"; pal.markerWrite(fad2_nl);
            }
            if (kind == type_mod.TypeKind.slice_type) {
                var elem = self.ctx.registry.slice_items[@intCast(usize, ty.payload_idx)].elem;
                var len_s: []const u8 = "len";
                var len_id = si_mod.stringInternerIntern(self.ctx.registry.interner, len_s);
                if (field_name_id == len_id) {
                    var f4sl: []const u8 = "F4SL\n"; pal.markerWrite(f4sl);
                    tid = nextTemp(self, type_mod.TYPE_USIZE);
                    var sl_nid = nameMapGet(self, base_temp);
                    emitInst(self, LirInst{ .load_field = .{ .name_id = sl_nid, .base = base_temp, .field_id = type_mod.SLICE_FIELD_LEN, .result = tid } });
                } else {
                    var pty = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, elem, false);
                    tid = nextTemp(self, pty);
                    var pm: []const u8 = "P:"; pal.markerWriteInt(pm, @intCast(u32, pty));
                    var psm: []const u8 = "Ps:"; pal.markerWriteInt(psm, tid);
                    var sp_nid = nameMapGet(self, base_temp);
                    emitInst(self, LirInst{ .load_field = .{ .name_id = sp_nid, .base = base_temp, .field_id = type_mod.SLICE_FIELD_PTR, .result = tid } });
                }
                return tid;
            } else if (kind == type_mod.TypeKind.array_type) {
                var len_s: []const u8 = "len";
                var len_id = si_mod.stringInternerIntern(self.ctx.registry.interner, len_s);
                if (field_name_id == len_id) {
                    var ap = self.ctx.registry.array_items[@intCast(usize, ty.payload_idx)];
                    var fam_m: []const u8 = "FAM:ALEN\n"; pal.markerWrite(fam_m);
                    tid = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, ap.length), .result = tid } });
                }
                return tid;
            } else if (kind == type_mod.TypeKind.struct_type or kind == type_mod.TypeKind.union_type or kind == type_mod.TypeKind.packed_union_type or kind == type_mod.TypeKind.tagged_union_type) {
                var gape_fkb: []const u8 = "GAPE:fkb\n"; pal.markerWrite(gape_fkb);
                if (kind == type_mod.TypeKind.tagged_union_type) {
                    var tp2 = self.ctx.registry.tu_items[@intCast(usize, ty.payload_idx)];
                    var tstart: usize = @intCast(usize, tp2.fields_start);
                    var tcount: usize = @intCast(usize, tp2.fields_count);
                    var tfi: usize = 0;
                    var is_type_base: u8 = @intCast(u8, 0);
                    if (self.ctx.has_symbols != @intCast(u8, 0)) {
                        if (base_node.kind == AstKind.ident_expr) {
                            var bb_name = ast_mod.astStoreIdentifier(store, node.child_0);
                            var bsym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, bb_name);
                            if (bsym) |bs| {
                                if (bs.kind == sym_mod.SymbolKind.type_alias) {
                                    is_type_base = @intCast(u8, 1);
                                } else if (bs.kind == sym_mod.SymbolKind.global) {
                                    if (bs.type_id < @intCast(u32, self.ctx.registry.types_len)) {
                                        var bst = self.ctx.registry.types_items[@intCast(usize, bs.type_id)];
                                        if (bst.name_id != @intCast(u32, 0) and bst.name_id == bb_name) { is_type_base = @intCast(u8, 1); }
                                    }
                                }
                            }
                        } else if (base_node.kind == AstKind.field_access) {
                            var fb_base = ast_mod.astStoreNodeAt(store, base_node.child_0);
                            if (fb_base.kind == AstKind.ident_expr) {
                                var fb_name = ast_mod.astStoreIdentifier(store, base_node.child_0);
                                var fbsym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, fb_name);
                                if (fbsym) |fs| {
                                    if (fs.kind == sym_mod.SymbolKind.module) {
                                        var mbr = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, fs.module_id, ast_mod.astStoreNodePayload(store, node.child_0));
                                        if (mbr) |ms| {
                                            if (ms.kind == sym_mod.SymbolKind.type_alias) {
                                                is_type_base = @intCast(u8, 1);
                                            } else if (ms.kind == sym_mod.SymbolKind.global) {
                                                if (ms.type_id < @intCast(u32, self.ctx.registry.types_len)) {
                                                    var mst = self.ctx.registry.types_items[@intCast(usize, ms.type_id)];
                                                    if (mst.name_id != @intCast(u32, 0) and mst.name_id == ast_mod.astStoreNodePayload(store, node.child_0)) { is_type_base = @intCast(u8, 1); }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    while (tfi < tcount) : (tfi += 1) {
                        if (self.ctx.registry.fe_items[tstart + tfi].name_id == field_name_id) {
                            var gape_fki: []const u8 = "GAPE:fki"; pal.markerWriteInt(gape_fki, @intCast(u32, tfi));
                            var var_fe = self.ctx.registry.fe_items[tstart + tfi];
                            if (var_fe.type_id != type_mod.TYPE_VOID and is_type_base == @intCast(u8, 0)) {
                                var payload_temp = nextTemp(self, var_fe.type_id);
                                var sf_nid = nameMapGet(self, base_temp);
                                emitInst(self, LirInst{ .load_field = .{ .name_id = sf_nid, .base = base_temp, .field_id = type_mod.TU_FIELD_PAYLOAD, .result = payload_temp } });
                                return payload_temp;
                            }
                            return emitTaggedUnionInit(self, type_box[0], @intCast(u32, tfi));
                        }
                    }
                    var gape_fno: []const u8 = "GAPE:fno\n"; pal.markerWrite(gape_fno);
                    var payload_s: []const u8 = "payload";
                    var payload_id = si_mod.stringInternerIntern(self.ctx.registry.interner, payload_s);
                    if (field_name_id == payload_id and fa_box[0] != type_mod.TYPE_VOID) {
                        var gape_fpl: []const u8 = "GAPE:fpl\n"; pal.markerWrite(gape_fpl);
                        var sf_nid = nameMapGet(self, base_temp);
                        emitInst(self, LirInst{ .load_field = .{ .name_id = sf_nid, .base = base_temp, .field_id = type_mod.TU_FIELD_PAYLOAD, .result = tid } });
                        return tid;
                    }
                    var tag_s: []const u8 = "tag";
                    var tag_id = si_mod.stringInternerIntern(self.ctx.registry.interner, tag_s);
                    if (field_name_id == tag_id) {
                        var gape_ftg: []const u8 = "GAPE:ftg\n"; pal.markerWrite(gape_ftg);
                        var sf_nid = nameMapGet(self, base_temp);
                        emitInst(self, LirInst{ .load_field = .{ .name_id = sf_nid, .base = base_temp, .field_id = type_mod.TU_FIELD_TAG, .result = tid } });
                        return tid;
                    }
                } else {
                var fields: []FieldEntry = undefined;
                if (kind == type_mod.TypeKind.union_type or kind == type_mod.TypeKind.packed_union_type) {
                    type_mod.typeRegistryGetUnionFields(self.ctx.registry, type_box[0], &fields);
                } else {
                    type_mod.typeRegistryGetStructFields(self.ctx.registry, type_box[0], &fields);
                }
                var gape_flen: []const u8 = "GAPE:flen"; pal.markerWriteInt(gape_flen, @intCast(u32, fields.len));
                var fi: usize = 0;
                while (fi < fields.len) : (fi += 1) {
                    if (fields[fi].name_id == field_name_id) {
                        var gape_fki: []const u8 = "GAPE:fki"; pal.markerWriteInt(gape_fki, @intCast(u32, fi));
                        var sf_nid = nameMapGet(self, base_temp);
                        if (kind == type_mod.TypeKind.struct_type) {
                            var pk_fields: []type_mod.PackedBitField = undefined;
                            if (type_mod.typeRegistryGetPackedBitFields(self.ctx.registry, type_box[0], &pk_fields)) {
                                if (fi < pk_fields.len) {
                                    if (fields[fi].type_id < @intCast(u32, self.ctx.registry.types_len)) {
                                        var mty = self.ctx.registry.types_items[@intCast(usize, fields[fi].type_id)];
                                        if (mty.kind == type_mod.TypeKind.struct_type and (mty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                                            var wrv_msg: []const u8 = "cannot read a whole packed-struct value out of a nested packed-struct field (bit-slice load not supported)";
                                            _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wrv_msg);
                                            return tid;
                                        }
                                    }
                                    var pkf = pk_fields[fi];
                                    emitInst(self, LirInst{ .load_bitfield = .{ .base = base_temp, .result = tid, .name_id = sf_nid, .bit_offset = pkf.bit_offset, .bit_width = @intCast(u32, pkf.bit_width) } });
                                    return tid;
                                }
                            }
                        } else if (kind == type_mod.TypeKind.packed_union_type) {
                            var pk_fields: []type_mod.PackedBitField = undefined;
                            if (type_mod.typeRegistryGetPackedUnionBitFields(self.ctx.registry, type_box[0], &pk_fields)) {
                                if (fi < pk_fields.len) {
                                    if (fields[fi].type_id < @intCast(u32, self.ctx.registry.types_len)) {
                                        var mty = self.ctx.registry.types_items[@intCast(usize, fields[fi].type_id)];
                                        if (mty.kind == type_mod.TypeKind.struct_type and (mty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                                            var wrv_msg: []const u8 = "cannot read a whole packed-struct value out of a packed union member (bit-slice load not supported)";
                                            _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wrv_msg);
                                            return tid;
                                        }
                                    }
                                    var pkf = pk_fields[fi];
                                    emitInst(self, LirInst{ .load_bitfield = .{ .base = base_temp, .result = tid, .name_id = sf_nid, .bit_offset = pkf.bit_offset, .bit_width = @intCast(u32, pkf.bit_width) } });
                                    return tid;
                                }
                            }
                        }
                        emitInst(self, LirInst{ .load_field = .{ .name_id = sf_nid, .base = base_temp, .field_id = @intCast(u32, fi), .result = tid } });
                        return tid;
                    }
            var gape_fno: []const u8 = "GAPE:fno\n"; pal.markerWrite(gape_fno);
            }
                }
            } else if (kind == type_mod.TypeKind.enum_type) {
                var ep2 = self.ctx.registry.en_items[@intCast(usize, ty.payload_idx)];
                var estart2: usize = @intCast(usize, ep2.members_start);
                var ecount2: usize = @intCast(usize, ep2.members_count);
                var ei2: usize = 0;
                while (ei2 < ecount2) : (ei2 += 1) {
                    var member2 = self.ctx.registry.em_items[estart2 + ei2];
                    if (member2.name_id == field_name_id) {
                        var eftid2 = nextTemp(self, type_id);
                        emitInst(self, LirInst{ .enum_const = .{ .value = @intCast(u64, member2.value), .result = eftid2, .type_id = type_id, .member_name_id = member2.name_id } });
                        return eftid2;
                    }
                }
            }
        }
        if (fa_box[0] == type_mod.TYPE_VOID) { var gape_frt: []const u8 = "GAPE:frt\n"; pal.markerWrite(gape_frt); }
        return tid;
    } else if (node.kind == AstKind.fn_call) {
        var d9m: []const u8 = "D9:FCk"; pal.markerWrite(d9m);
        var callee_head = ast_mod.astStoreNodeAt(store, node.child_0);
        var ck_val: u8 = callee_head.kind;
        var d9kb: [10]u8 = undefined; var d9kl = itoa_mod.itoa(@intCast(u32, ck_val), d9kb[0..]); var d9ks: usize = @intCast(usize, 9) - @intCast(usize, d9kl); pal.markerWrite(d9kb[d9ks..@intCast(usize, 9)]);
        var d9sp: []const u8 = " "; pal.markerWrite(d9sp);
         var ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
         var prt2_m: []const u8 = "PRT2:l"; pal.markerWrite(prt2_m);
         var prt2_lb: [10]u8 = undefined; var prt2_ll = itoa_mod.itoa(@intCast(u32, ec.len), prt2_lb[0..]); var prt2_ls: usize = @intCast(usize, 9) - @intCast(usize, prt2_ll); pal.markerWrite(prt2_lb[prt2_ls..@intCast(usize, 9)]);
         var ei2: usize = @intCast(usize, 0);
         while (ei2 < ec.len and ei2 < @intCast(usize, 4)) : (ei2 += @intCast(usize, 1)) {
             var ck2: u32 = @intCast(u32, @enumToInt(ast_mod.astStoreNodeAt(store, ec[ei2]).kind));
             var p2m: []const u8 = "k"; pal.markerWrite(p2m);
             var p2b: [10]u8 = undefined; var p2l = itoa_mod.itoa(ck2, p2b[0..]); var p2s: usize = @intCast(usize, 9) - @intCast(usize, p2l); pal.markerWrite(p2b[p2s..@intCast(usize, 9)]);
         }
           var prt2_nl: []const u8 = "\n"; pal.markerWrite(prt2_nl);
          var d9p_m: []const u8 = "D9:p"; pal.markerWrite(d9p_m);
        var d9p_b: [20]u8 = undefined; var d9p_l = itoa_mod.itoa(@intCast(u32, ast_mod.astStoreNodePayloadPacked(store, node_idx, node.kind) & @intCast(u64, 0xFFFFFFFF)), d9p_b[0..]); var d9p_s: usize = @intCast(usize, 19) - @intCast(usize, d9p_l); pal.markerWrite(d9p_b[d9p_s..@intCast(usize, 19)]);
         var d9p_nl: []const u8 = "\n"; pal.markerWrite(d9p_nl);
         var callee_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
         if (callee_rt) |crt| {
            var crt_ty = self.ctx.registry.types_items[@intCast(usize, crt)];
            if (crt_ty.kind == type_mod.TypeKind.fn_type) {
                 var fp = self.ctx.registry.fn_items[@intCast(usize, crt_ty.payload_idx)];
                  var fnt_nm: []const u8 = "FNT:N"; pal.markerWriteInt(fnt_nm, fp.name_id);
                  var fnt_rm: []const u8 = "FNT:R"; pal.markerWriteInt(fnt_rm, fp.return_type);
                   if (fp.name_id == self.print_fn_id and ec.len >= @intCast(usize, 2)) {
                      var prn_m: []const u8 = "PRN:c"; pal.markerWrite(prn_m);
                      var prn_cb: [10]u8 = undefined; var prn_cl = itoa_mod.itoa(@intCast(u32, ec.len), prn_cb[0..]); var prn_cs: usize = @intCast(usize, 9) - @intCast(usize, prn_cl); pal.markerWrite(prn_cb[prn_cs..@intCast(usize, 9)]);
                      var prn_nm: []const u8 = "n"; pal.markerWrite(prn_nm);
                      var prn_nb: [10]u8 = undefined; var prn_nl = itoa_mod.itoa(fp.name_id, prn_nb[0..]); var prn_ns: usize = @intCast(usize, 9) - @intCast(usize, prn_nl); pal.markerWrite(prn_nb[prn_ns..@intCast(usize, 9)]);
                      var prn_xl: []const u8 = "\n"; pal.markerWrite(prn_xl);
                      if (ec.len > @intCast(usize, 0)) {
                      var e0m: []const u8 = "E0:p"; pal.markerWrite(e0m);
                      var e0b: [10]u8 = undefined; var e0l = itoa_mod.itoa(@intCast(u32, @enumToInt(ast_mod.astStoreNodeAt(store, ec[0]).kind)), e0b[0..]); var e0s: usize = @intCast(usize, 9) - @intCast(usize, e0l); pal.markerWrite(e0b[e0s..@intCast(usize, 9)]);
                      var e01m: []const u8 = "n"; pal.markerWrite(e01m);
                      var e01b: [10]u8 = undefined; var e01l = itoa_mod.itoa(ast_mod.astStoreNodePayload(store, ec[0]), e01b[0..]); var e01s: usize = @intCast(usize, 9) - @intCast(usize, e01l); pal.markerWrite(e01b[e01s..@intCast(usize, 9)]);
                      var e02m: []const u8 = "i"; pal.markerWrite(e02m);
                      var e02b: [10]u8 = undefined; var e02l = itoa_mod.itoa(ast_mod.astStoreIdentifier(store, ec[0]), e02b[0..]); var e02s: usize = @intCast(usize, 9) - @intCast(usize, e02l); pal.markerWrite(e02b[e02s..@intCast(usize, 9)]);
                      var e0nl: []const u8 = "\n"; pal.markerWrite(e0nl);
                      }
                       var pfmtn = ast_mod.astStoreNodeAt(store, ec[0]);
                       if (pfmtn.kind == AstKind.string_literal) {
                           var pfsid: u32 = ast_mod.astStoreNodePayload(store, ec[0]);
                           if (@intCast(usize, ast_mod.astStoreNodePayload(store, ec[0])) < store.string_values.len) { pfsid = store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(store, ec[0]))]; }
                           var pfbytes = si_mod.stringInternerGet(self.ctx.registry.interner, pfsid);
                           var pan = ast_mod.astStoreNodeAt(store, ec[ec.len - @intCast(usize, 1)]);
                           var pae = ast_mod.astStoreNodeExtraChildren(store, ec[ec.len - @intCast(usize, 1)]);
                           lowerPrintFmt(self, ec[0], pfbytes, pae);
                       }
                        return @intCast(u32, 0);
                   }
                        var args_start = self.temp_counter;
                      var ai: usize = 0;
                      while (ai < ec.len) : (ai += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                      ai = 0;
                var is_ex: u8 = fp.is_extern;
                while (ai < ec.len) : (ai += 1) {
                    var arg_val = lowerExpr(self, ec[ai]);
                    if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| {
                        if (pt != type_mod.TYPE_UNDEFINED and is_ex == @intCast(u8, 0)) {
                            var st = getTempType(self, arg_val);
                            if (st == type_mod.TYPE_NULL) { var cs5_m: []const u8 = "CS5\n"; pal.markerWrite(cs5_m); }
                            var ck = coercion_mod.classifyCoercion(self.ctx.registry, st, pt);
                            var ce: CoercionEntry = undefined;
                            ce.node_idx = ec[ai];
                            ce.kind = ck;
                            ce.target_type = pt;
                            arg_val = applyCoercion(self, arg_val, ce);
                        }
                        if (is_ex == @intCast(u8, 1) and pt != type_mod.TYPE_UNDEFINED) {
                            var et = self.ctx.registry.types_items[@intCast(usize, pt)];
                            if (et.kind == type_mod.TypeKind.optional_type) {
                                var eo = self.ctx.registry.opt_items[@intCast(usize, et.payload_idx)];
                                self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = eo.payload;
                                if (@intCast(usize, arg_val) < self.hoisted_temps.len and getTempType(self, arg_val) != type_mod.TYPE_NULL) {
                                    var ua = nextTemp(self, eo.payload);
                                    emitInst(self, LirInst{ .unwrap_optional_abi = .{ .value = arg_val, .result = ua } });
                                    arg_val = ua;
                                }
                            }
                        }
                    }
                    emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = args_start + @intCast(u32, ai), .src = arg_val } });
                    var sbox: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                    if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| { sbox[0] = pt; }
                    else { sbox[0] = self.hoisted_temps.items[@intCast(usize, arg_val)].type_id; }
                    self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = sbox[0];
                    if (is_ex == @intCast(u8, 1) and sbox[0] != type_mod.TYPE_UNDEFINED) {
                        var sti = self.ctx.registry.types_items[@intCast(usize, sbox[0])];
                        if (sti.kind == type_mod.TypeKind.optional_type) {
                            var sio = self.ctx.registry.opt_items[@intCast(usize, sti.payload_idx)];
                            self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = sio.payload;
                        }
                    }
                }
                var result: u32 = @intCast(u32, 0);
                var optva_m: []const u8 = "OPTVOID:rt"; pal.markerWriteInt(optva_m, fp.return_type);
                if (fp.return_type != type_mod.TYPE_VOID and fp.return_type != type_mod.TYPE_UNDEFINED) {
                    var vffc_m: []const u8 = "VFLOW:fvret\n"; pal.markerWrite(vffc_m);
                    result = nextTemp(self, fp.return_type);
                }
                var optvb_m: []const u8 = "OPTVOID:res"; pal.markerWriteInt(optvb_m, result);
                 var fnr_rm: []const u8 = "FNR:R"; pal.markerWriteInt(fnr_rm, fp.return_type);
                 var fnr_tm: []const u8 = "FNR:T"; pal.markerWriteInt(fnr_tm, result);
                  var call_name: u32 = fp.name_id;
                 var cd_slot = lir_mod.lirSideAppendCallDirect(self.func, .{ .name_id = call_name, .module_id = fp.module_id, .args_start = args_start, .args_count = @intCast(u32, ec.len), .result = result, .return_type = fp.return_type, .is_extern = fp.is_extern });
                 emitInst(self, LirInst{ .call_direct = cd_slot });
                 return result;
               }
             else if (crt_ty.kind == type_mod.TypeKind.ptr_type) {
                 var fptr_pp = self.ctx.registry.ptr_items[@intCast(usize, crt_ty.payload_idx)];
                 var fptr_pointee = self.ctx.registry.types_items[@intCast(usize, fptr_pp.base)];
                 if (fptr_pointee.kind == type_mod.TypeKind.fn_type) {
                     var fpfp = self.ctx.registry.fn_items[@intCast(usize, fptr_pointee.payload_idx)];
                     var fpi_callee = lowerExpr(self, node.child_0);
                     var fpi_args_start = self.temp_counter;
                     var fpi_ai: usize = @intCast(usize, 0);
                     while (fpi_ai < ec.len) : (fpi_ai += @intCast(usize, 1)) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                     fpi_ai = @intCast(usize, 0);
                     while (fpi_ai < ec.len) : (fpi_ai += @intCast(usize, 1)) {
                         var fpi_arg = lowerExpr(self, ec[fpi_ai]);
                         if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[fpi_ai])) |fpi_pt| {
                             if (fpi_pt != type_mod.TYPE_UNDEFINED) {
                                 var st = getTempType(self, fpi_arg);
                                  if (st == type_mod.TYPE_NULL) { var cs6_m: []const u8 = "CS6\n"; pal.markerWrite(cs6_m); }
                                  var ck = coercion_mod.classifyCoercion(self.ctx.registry, st, fpi_pt);
                                 var ce: CoercionEntry = undefined;
                                 ce.node_idx = ec[fpi_ai];
                                 ce.kind = ck;
                                 ce.target_type = fpi_pt;
                                 fpi_arg = applyCoercion(self, fpi_arg, ce);
                             }
                         }
                         emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = fpi_args_start + @intCast(u32, fpi_ai), .src = fpi_arg } });
                         var fpi_slot: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                         if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[fpi_ai])) |fpi_pt| { fpi_slot[0] = fpi_pt; }
                         else { fpi_slot[0] = self.hoisted_temps.items[@intCast(usize, fpi_arg)].type_id; }
                         self.hoisted_temps.items[@intCast(usize, fpi_args_start) + fpi_ai].type_id = fpi_slot[0];
                     }
                     var fpi_result: u32 = @intCast(u32, 0);
                     if (fpfp.return_type != type_mod.TYPE_VOID and fpfp.return_type != type_mod.TYPE_UNDEFINED) {
                         fpi_result = nextTemp(self, fpfp.return_type);
                     }
                     var fpim: []const u8 = "FNI:t"; pal.markerWriteInt(fpim, fpi_result);
                     emitInst(self, LirInst{ .call = .{ .callee = fpi_callee, .args_start = fpi_args_start, .args_count = @intCast(u32, ec.len), .result = fpi_result } });
                     return fpi_result;
                 }
             }
          }
        var callee_node = ast_mod.astStoreNodeAt(store, node.child_0);
        if (callee_node.kind == @enumToInt(AstKind.field_access)) {
            var dfa: []const u8 = "DFA:ck="; pal.markerWrite(dfa);
            var ckv: u8 = callee_node.kind; var dfab: [10]u8 = undefined; var dfal = itoa_mod.itoa(@intCast(u32, ckv), dfab[0..]); var dfas: usize = @intCast(usize, 9) - @intCast(usize, dfal); pal.markerWrite(dfab[dfas..@intCast(usize, 9)]);
            var dfasp: []const u8 = "\n"; pal.markerWrite(dfasp);
            var bnode = ast_mod.astStoreNodeAt(store, callee_node.child_0);
            var bkv: u8 = bnode.kind; var bfb: [10]u8 = undefined; var bfl = itoa_mod.itoa(@intCast(u32, bkv), bfb[0..]); var bfs: usize = @intCast(usize, 9) - @intCast(usize, bfl); pal.markerWrite(bfb[bfs..@intCast(usize, 9)]); var bfsp: []const u8 = "bk\n"; pal.markerWrite(bfsp);
            var base_node = bnode;
            if (base_node.kind == AstKind.ident_expr or base_node.kind == @enumToInt(AstKind.field_access)) {
            var field_name_id: u32 = ast_mod.astStoreNodePayload(store, node.child_0);
            var base_node_idx: u32 = callee_node.child_0;
            if (base_node.kind == @enumToInt(AstKind.field_access)) {
                    var chain: [4]u32 = undefined;
                    var chain_len: u32 = @intCast(u32, 0);
                    chain[@intCast(usize, chain_len)] = ast_mod.astStoreNodePayload(store, node.child_0); chain_len += @intCast(u32, 1);
                    var cw = base_node;
                    var cw_idx: u32 = callee_node.child_0;
                    while (cw.kind == @enumToInt(AstKind.field_access)) {
                        chain[@intCast(usize, chain_len)] = ast_mod.astStoreNodePayload(store, cw_idx); chain_len += @intCast(u32, 1);
                        cw_idx = cw.child_0;
                        cw = ast_mod.astStoreNodeAt(store, cw_idx);
                    }
                    if (cw.kind != @enumToInt(AstKind.ident_expr)) { return @intCast(u32, 0); }
                    base_node = cw;
                    base_node_idx = cw_idx;
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
                    var chain_ok: []const u8 = "CHAIN:r\n"; pal.markerWrite(chain_ok);
                }
                var base_name_id = ast_mod.astStoreIdentifier(store, base_node_idx);
                var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, base_name_id);
                if (sym) |sm| {
                    var d5m: []const u8 = "D5:sm="; pal.markerWrite(d5m);
                    var d5mb: [10]u8 = undefined; var d5ml = itoa_mod.itoa(sm.module_id, d5mb[0..]); var d5ms: usize = @intCast(usize, 9) - @intCast(usize, d5ml); pal.markerWrite(d5mb[d5ms..@intCast(usize, 9)]);
                    var d5bn: []const u8 = "bn"; pal.markerWrite(d5bn);
                    var d5bnb: [10]u8 = undefined; var d5bnl = itoa_mod.itoa(base_name_id, d5bnb[0..]); var d5bns: usize = @intCast(usize, 9) - @intCast(usize, d5bnl); pal.markerWrite(d5bnb[d5bns..@intCast(usize, 9)]);
                    var d5nl: []const u8 = " "; pal.markerWrite(d5nl);
                    if (sm.module_id != @intCast(u32, 0) and sm.module_id != self.module_id) {
                        var dz1_m: []const u8 = "DZ1:PASS\n"; pal.markerWrite(dz1_m);
                        var target_mod_id = sm.module_id;
                        var field_name_id: u32 = ast_mod.astStoreNodePayload(store, node.child_0);
                        var field_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, target_mod_id, field_name_id);
                        if (field_sym) |fs| { var a3: []const u8 = "F3a1"; pal.markerWrite(a3);
                            if (fs.kind == @intCast(u8, 3)) {
                                 var call_ns: u32 = self.temp_counter;
                                 var ai: usize = 0;
                                 while (ai < ec.len) : (ai += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                                 ai = 0;
                                  var is_ex: u8 = @intCast(u8, if ((fs.flags & @intCast(u16, 4)) != @intCast(u16, 0)) @intCast(usize, 1) else @intCast(usize, 0));
                                  while (ai < ec.len) : (ai += 1) {
                                       var call_val = lowerExpr(self, ec[ai]);
                                       if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| {
                                           if (pt != type_mod.TYPE_UNDEFINED and is_ex == @intCast(u8, 0)) {
                                               var st = getTempType(self, call_val);
                                                if (st == type_mod.TYPE_NULL) { var cs7_m: []const u8 = "CS7\n"; pal.markerWrite(cs7_m); }
                                                var ck = coercion_mod.classifyCoercion(self.ctx.registry, st, pt);
                                               var ce: CoercionEntry = undefined;
                                               ce.node_idx = ec[ai];
                                               ce.kind = ck;
                                               ce.target_type = pt;
                                               call_val = applyCoercion(self, call_val, ce);
                                           }
                                           if (is_ex == @intCast(u8, 1) and pt != type_mod.TYPE_UNDEFINED) {
                                               var et = self.ctx.registry.types_items[@intCast(usize, pt)];
                                               if (et.kind == type_mod.TypeKind.optional_type) {
                                                   var eo = self.ctx.registry.opt_items[@intCast(usize, et.payload_idx)];
                                                   if (@intCast(usize, call_val) < self.hoisted_temps.len and getTempType(self, call_val) != type_mod.TYPE_NULL) {
                                                       var ua = nextTemp(self, eo.payload);
                                                       emitInst(self, LirInst{ .unwrap_optional_abi = .{ .value = call_val, .result = ua } });
                                                       call_val = ua;
                    }
                }
            }
        }
                                       emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = call_ns + @intCast(u32, ai), .src = call_val } });
                                       var slot_tid_a: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                                       if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt2| { slot_tid_a[0] = pt2; var hx: []const u8 = "H"; pal.markerWrite(hx); }
                                       else { slot_tid_a[0] = self.hoisted_temps.items[@intCast(usize, call_val)].type_id; var mx: []const u8 = "M"; pal.markerWrite(mx); }
                                       self.hoisted_temps.items[@intCast(usize, call_ns) + ai].type_id = slot_tid_a[0];
                                       if (is_ex == @intCast(u8, 1) and slot_tid_a[0] != type_mod.TYPE_UNDEFINED) {
                                           var sti = self.ctx.registry.types_items[@intCast(usize, slot_tid_a[0])];
                                           if (sti.kind == type_mod.TypeKind.optional_type) {
                                               var sio = self.ctx.registry.opt_items[@intCast(usize, sti.payload_idx)];
                                               self.hoisted_temps.items[@intCast(usize, call_ns) + ai].type_id = sio.payload;
                                           }
                                       }
                                  }
                                 var args_count: u32 = @intCast(u32, ec.len);
                                 self._fn_ret_type = type_mod.TYPE_UNDEFINED;
                                 if (fs.decl_node != 0) {
                                     var dn = ast_mod.astStoreNodeAt(store, fs.decl_node);
                                     if (dn.kind == @enumToInt(AstKind.fn_decl)) {
                                         var proto = store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(store, fs.decl_node))];
                                         if (proto.return_type_node != 0) {
                                             var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, proto.return_type_node);
                                             if (rt) |_| { var dx: []const u8 = "HX"; pal.markerWrite(dx); } else { var dx: []const u8 = "MX"; pal.markerWrite(dx); }
                                              if (rt) |t| { self._fn_ret_type = t; }
                                         }
                                     }
                                 }
                                 var result: u32 = @intCast(u32, 0);
                                 if (self._fn_ret_type != type_mod.TYPE_VOID and self._fn_ret_type != type_mod.TYPE_UNDEFINED) {
                                     var c3m: []const u8 = "C3:"; pal.markerWrite(c3m);
                                     var c3b: [20]u8 = undefined; var c3l = itoa_mod.itoa(self._fn_ret_type, c3b[0..]); var c3s: usize = @intCast(usize, 19) - @intCast(usize, c3l); pal.markerWrite(c3b[c3s..@intCast(usize, 19)]);
                                     var c3nl: []const u8 = "\n"; pal.markerWrite(c3nl);
                                     result = nextTemp(self, self._fn_ret_type);
                                 }
                                    var ad3m: []const u8 = "ADX:n"; pal.markerWrite(ad3m);
                                    var adx1b: [10]u8 = undefined; var adx1l = itoa_mod.itoa(fs.name_id, adx1b[0..]); var adx1s: usize = @intCast(usize, 9) - @intCast(usize, adx1l); pal.markerWrite(adx1b[adx1s..@intCast(usize, 9)]);
                                    var adx1m: []const u8 = "m"; pal.markerWrite(adx1m);
                                    var adx1mb: [10]u8 = undefined; var adx1ml = itoa_mod.itoa(target_mod_id, adx1mb[0..]); var adx1ms: usize = @intCast(usize, 9) - @intCast(usize, adx1ml); pal.markerWrite(adx1mb[adx1ms..@intCast(usize, 9)]);
                                    var adx1nl: []const u8 = "\n"; pal.markerWrite(adx1nl);
                                     var cd2_slot = lir_mod.lirSideAppendCallDirect(self.func, .{ .name_id = fs.name_id, .module_id = target_mod_id, .args_start = call_ns, .args_count = args_count, .result = result, .return_type = self._fn_ret_type, .is_extern = @intCast(u8, if ((fs.flags & @intCast(u16, 4)) != @intCast(u16, 0)) @intCast(usize, 1) else @intCast(usize, 0)) });
                                     emitInst(self, LirInst{ .call_direct = cd2_slot });
    var lex_rt_m: []const u8 = "r"; pal.markerWrite(lex_rt_m);
    var lex_rt_b: [10]u8 = undefined; var lex_rt_l = itoa_mod.itoa(result, lex_rt_b[0..]); var lex_rt_s: usize = @intCast(usize, 9) - @intCast(usize, lex_rt_l); pal.markerWrite(lex_rt_b[lex_rt_s..@intCast(usize, 9)]);
    var lex_rt_nl: []const u8 = "\n"; pal.markerWrite(lex_rt_nl);
    return result;
                            } else { var fk_val: u8 = fs.kind; var a3f: []const u8 = "F3aKk"; pal.markerWrite(a3f); var a3fkb: [10]u8 = undefined; var a3fkl = itoa_mod.itoa(@intCast(u32, fk_val), a3fkb[0..]); var a3fks: usize = @intCast(usize, 9) - @intCast(usize, a3fkl); pal.markerWrite(a3fkb[a3fks..@intCast(usize, 9)]); var a3fsp: []const u8 = "\n"; pal.markerWrite(a3fsp); }
                        } else { var a3m: []const u8 = "DZ1:NF"; pal.markerWrite(a3m); var a3mb: [10]u8 = undefined; var a3ml = itoa_mod.itoa(field_name_id, a3mb[0..]); var a3ms: usize = @intCast(usize, 9) - @intCast(usize, a3ml); pal.markerWrite(a3mb[a3ms..@intCast(usize, 9)]); var a3mns: []const u8 = " "; pal.markerWrite(a3mns); }
                    } else { var dz1_fail: []const u8 = "DZ1:MSKIP\n"; pal.markerWrite(dz1_fail); }
                } else { var a3b: []const u8 = "F3aBn"; pal.markerWrite(a3b); var a3bb: [10]u8 = undefined; var a3bl = itoa_mod.itoa(base_name_id, a3bb[0..]); var a3bs: usize = @intCast(usize, 9) - @intCast(usize, a3bl); pal.markerWrite(a3bb[a3bs..@intCast(usize, 9)]); var a3bns: []const u8 = " "; pal.markerWrite(a3bns); }
            }
        } else if (callee_node.kind == @enumToInt(AstKind.ident_expr)) {
            var callee_name_id = ast_mod.astStoreIdentifier(store, node.child_0);
            var sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, self.module_id, callee_name_id);
            if (sym) |sm| { var sf: []const u8 = "S"; pal.markerWrite(sf);
                if (sm.kind == @intCast(u8, 0)) { var d3m: []const u8 = "D3:SKIPn"; pal.markerWrite(d3m); var d3nb: [10]u8 = undefined; var d3nl = itoa_mod.itoa(callee_name_id, d3nb[0..]); var d3ns: usize = @intCast(usize, 9) - @intCast(usize, d3nl); pal.markerWrite(d3nb[d3ns..@intCast(usize, 9)]); var d3kn: []const u8 = "k0"; pal.markerWrite(d3kn); }
                else if (sm.kind == @intCast(u8, 1)) { var d3m: []const u8 = "D3:SKIPn"; pal.markerWrite(d3m); var d3nb: [10]u8 = undefined; var d3nl = itoa_mod.itoa(callee_name_id, d3nb[0..]); var d3ns: usize = @intCast(usize, 9) - @intCast(usize, d3nl); pal.markerWrite(d3nb[d3ns..@intCast(usize, 9)]); var d3kn: []const u8 = "k1"; pal.markerWrite(d3kn); }
                else if (sm.kind == @intCast(u8, 2) or sm.kind == @intCast(u8, 3)) { var d3m: []const u8 = "D3:OKn"; pal.markerWrite(d3m); var d3nb: [10]u8 = undefined; var d3nl = itoa_mod.itoa(callee_name_id, d3nb[0..]); var d3ns: usize = @intCast(usize, 9) - @intCast(usize, d3nl); pal.markerWrite(d3nb[d3ns..@intCast(usize, 9)]); var d3kn: []const u8 = "k"; pal.markerWrite(d3kn); var d3kb: [10]u8 = undefined; var d3kl = itoa_mod.itoa(sm.kind, d3kb[0..]); var d3ks: usize = @intCast(usize, 9) - @intCast(usize, d3kl); pal.markerWrite(d3kb[d3ks..@intCast(usize, 9)]);
                    var args_start = self.temp_counter;
                    var ai: usize = 0;
                    while (ai < ec.len) : (ai += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
                    ai = 0;
                    var is_ex: u8 = @intCast(u8, if ((sm.flags & @intCast(u16, 4)) != @intCast(u16, 0)) @intCast(usize, 1) else @intCast(usize, 0));
                    while (ai < ec.len) : (ai += 1) {
                        var arg_val = lowerExpr(self, ec[ai]);
                        if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt| {
                            if (pt != type_mod.TYPE_UNDEFINED and is_ex == @intCast(u8, 0)) {
                                var st = getTempType(self, arg_val);
                                if (st == type_mod.TYPE_NULL) { var cs8_m: []const u8 = "CS8\n"; pal.markerWrite(cs8_m); }
                                var ck = coercion_mod.classifyCoercion(self.ctx.registry, st, pt);
                                var ce: CoercionEntry = undefined;
                                ce.node_idx = ec[ai];
                                ce.kind = ck;
                                ce.target_type = pt;
                                arg_val = applyCoercion(self, arg_val, ce);
                            }
                            if (is_ex == @intCast(u8, 1) and pt != type_mod.TYPE_UNDEFINED) {
                                var et = self.ctx.registry.types_items[@intCast(usize, pt)];
                                if (et.kind == type_mod.TypeKind.optional_type) {
                                    var eo = self.ctx.registry.opt_items[@intCast(usize, et.payload_idx)];
                                    if (@intCast(usize, arg_val) < self.hoisted_temps.len and getTempType(self, arg_val) != type_mod.TYPE_NULL) {
                                        var ua = nextTemp(self, eo.payload);
                                        emitInst(self, LirInst{ .unwrap_optional_abi = .{ .value = arg_val, .result = ua } });
                                        arg_val = ua;
                                    }
                                }
                            }
                        }
                        emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = args_start + @intCast(u32, ai), .src = arg_val } });
                        var slot_tid_b: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
                        if (hash_mod.u32ToU32MapGet(self.ctx.call_arg_types, ec[ai])) |pt2| { slot_tid_b[0] = pt2; var hx2: u32 = 1; if (hx2 == 1) { var px: usize = 999999; hx2 = 0; } }
                        else { slot_tid_b[0] = getTempType(self, arg_val); var mx2: u32 = 2; if (mx2 == 2) { var qx: usize = 999998; mx2 = 0; } }
                        self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = slot_tid_b[0];
                        if (is_ex == @intCast(u8, 1) and slot_tid_b[0] != type_mod.TYPE_UNDEFINED) {
                            var sti = self.ctx.registry.types_items[@intCast(usize, slot_tid_b[0])];
                            if (sti.kind == type_mod.TypeKind.optional_type) {
                                var sio = self.ctx.registry.opt_items[@intCast(usize, sti.payload_idx)];
                                self.hoisted_temps.items[@intCast(usize, args_start) + ai].type_id = sio.payload;
                            }
                        }
                    }
                    var args_count: u32 = @intCast(u32, ec.len);
                    self._fn_ret_type = type_mod.TYPE_UNDEFINED;
                    if (sm.decl_node != 0) {
                        var dn = ast_mod.astStoreNodeAt(store, sm.decl_node);
                        if (dn.kind == @intCast(u8, 2)) {
                            var proto = store.fn_protos.items[@intCast(usize, ast_mod.astStoreNodePayload(store, sm.decl_node))];
                            if (proto.return_type_node != 0) {
                                var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, proto.return_type_node);
                                if (rt) |_| { var dd: []const u8 = "HD"; pal.markerWrite(dd); } else { var dd: []const u8 = "MD"; pal.markerWrite(dd); }
                                if (rt) |t| { self._fn_ret_type = t; }
                            }
                        }
                    }
                    var result: u32 = @intCast(u32, 0);
                    if (self._fn_ret_type != type_mod.TYPE_VOID and self._fn_ret_type != type_mod.TYPE_UNDEFINED) {
                        var vflr_m: []const u8 = "VFLOW:lvret\n"; pal.markerWrite(vflr_m);
                        var c3m2: []const u8 = "C3:"; pal.markerWrite(c3m2);
                        var c3b2: [20]u8 = undefined; var c3l2 = itoa_mod.itoa(self._fn_ret_type, c3b2[0..]); var c3s2: usize = @intCast(usize, 19) - @intCast(usize, c3l2); pal.markerWrite(c3b2[c3s2..@intCast(usize, 19)]);
                        var c3nl2: []const u8 = "\n"; pal.markerWrite(c3nl2);
                        result = nextTemp(self, self._fn_ret_type);
                    }
                    var fx2: []const u8 = "FNR2:n"; pal.markerWrite(fx2);
                    var fx2b: [10]u8 = undefined; var fx2l = itoa_mod.itoa(callee_name_id, fx2b[0..]); var fx2s: usize = @intCast(usize, 9) - @intCast(usize, fx2l); pal.markerWrite(fx2b[fx2s..@intCast(usize, 9)]);
                    var fx2rm: []const u8 = "r"; pal.markerWrite(fx2rm);
                    var fx2rb: [10]u8 = undefined; var fx2rl = itoa_mod.itoa(self._fn_ret_type, fx2rb[0..]); var fx2rs: usize = @intCast(usize, 9) - @intCast(usize, fx2rl); pal.markerWrite(fx2rb[fx2rs..@intCast(usize, 9)]);
                    var fx2tm: []const u8 = "t"; pal.markerWrite(fx2tm);
                    var fx2tb: [10]u8 = undefined; var fx2tl = itoa_mod.itoa(result, fx2tb[0..]); var fx2ts: usize = @intCast(usize, 9) - @intCast(usize, fx2tl); pal.markerWrite(fx2tb[fx2ts..@intCast(usize, 9)]);
                    var fxl2: []const u8 = "\n"; pal.markerWrite(fxl2);
                    var ad3m2: []const u8 = "ADX:n"; pal.markerWrite(ad3m2);
                    var adx2b: [10]u8 = undefined; var adx2l = itoa_mod.itoa(sm.name_id, adx2b[0..]); var adx2s: usize = @intCast(usize, 9) - @intCast(usize, adx2l); pal.markerWrite(adx2b[adx2s..@intCast(usize, 9)]);
                    var adx2m: []const u8 = "m"; pal.markerWrite(adx2m);
                    var adx2mb: [10]u8 = undefined; var adx2ml = itoa_mod.itoa(sm.module_id, adx2mb[0..]); var adx2ms: usize = @intCast(usize, 9) - @intCast(usize, adx2ml); pal.markerWrite(adx2mb[adx2ms..@intCast(usize, 9)]);
                    var adx2nl: []const u8 = "\n"; pal.markerWrite(adx2nl);
                    var cd3_slot = lir_mod.lirSideAppendCallDirect(self.func, .{ .name_id = sm.name_id, .module_id = sm.module_id, .args_start = args_start, .args_count = args_count, .result = result, .return_type = self._fn_ret_type, .is_extern = @intCast(u8, if ((sm.flags & @intCast(u16, 4)) != @intCast(u16, 0)) @intCast(usize, 1) else @intCast(usize, 0)) });
                    emitInst(self, LirInst{ .call_direct = cd3_slot });
                    return result;
                }
            }
        }
        var a3p: []const u8 = "F3aP"; pal.markerWrite(a3p);
        var f3rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (f3rt) |t| {
            var f3rb: [10]u8 = undefined; var f3rl = itoa_mod.itoa(t, f3rb[0..]); var f3rs: usize = @intCast(usize, 9) - @intCast(usize, f3rl);
            var f3pm: []const u8 = "F3P:rt"; pal.markerWrite(f3pm); pal.markerWrite(f3rb[f3rs..@intCast(usize, 9)]);
            var f3nl: []const u8 = "\n"; pal.markerWrite(f3nl);
        } else {
            var f3pn: []const u8 = "F3P:NULL\n"; pal.markerWrite(f3pn);
        }
        var callee_cn = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        var a3pt: [20]u8 = undefined; var a3ptl = itoa_mod.itoa(callee_cn.kind, a3pt[0..]); var a3pts: usize = @intCast(usize, 19) - @intCast(usize, a3ptl); pal.markerWrite(a3pt[a3pts..@intCast(usize, 19)]);
        if (callee_cn.kind == AstKind.ident_expr) {
            var a3pn: []const u8 = "n"; pal.markerWrite(a3pn);
            var a3pnb: [20]u8 = undefined; var a3pnl = itoa_mod.itoa(ast_mod.astStoreIdentifier(self.ctx.store, node.child_0), a3pnb[0..]); var a3pns: usize = @intCast(usize, 19) - @intCast(usize, a3pnl); pal.markerWrite(a3pnb[a3pns..@intCast(usize, 19)]);
        }
        var a3pnl: []const u8 = " "; pal.markerWrite(a3pnl);
        var callee_temp = lowerExpr(self, node.child_0);
        var args_start = self.temp_counter;
        var ai2: usize = 0;
        while (ai2 < ec.len) : (ai2 += 1) { _ = nextTemp(self, type_mod.TYPE_UNDEFINED); }
        ai2 = 0;
        while (ai2 < ec.len) : (ai2 += 1) {
            var arg_val = lowerExpr(self, ec[ai2]);
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = args_start + @intCast(u32, ai2), .src = arg_val } });
        }
        var d2s3: []const u8 = "D2I:ns="; pal.markerWrite(d2s3);
        dbgPrintU32(args_start); var d2n3: []const u8 = " nc="; pal.markerWrite(d2n3);
        dbgPrintU32(@intCast(u32, ec.len)); var d2nl3: []const u8 = "\n"; pal.markerWrite(d2nl3);
         var result = nextTemp(self, type_mod.TYPE_UNDEFINED);
        var und_ic_m: []const u8 = "UND:icRt"; pal.markerWrite(und_ic_m);
        var und_ic_tb: [10]u8 = undefined; var und_ic_tl = itoa_mod.itoa(result, und_ic_tb[0..]); var und_ic_ts: usize = @intCast(usize, 9) - @intCast(usize, und_ic_tl); pal.markerWrite(und_ic_tb[und_ic_ts..@intCast(usize, 9)]);
        var und_ic_nl: []const u8 = "\n"; pal.markerWrite(und_ic_nl);
        emitInst(self, LirInst{ .call = .{
            .callee = callee_temp,
            .args_start = args_start,
            .args_count = @intCast(u32, ec.len),
            .result = result,
        } });
        return result;
        } else if (node.kind == AstKind.builtin_call) {
         var ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
            if (node.child_0 == self.ptrtoint_name_id or node.child_0 == self.int_from_ptr_name_id) {
                if (ec.len >= 1) {
                    var arg_val = lowerExpr(self, ec[@intCast(usize, 0)]);
                    var result2 = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .ptr_to_int = .{ .value = arg_val, .result = result2 } });
                    return result2;
                } else {
                    return nextTemp(self, type_mod.TYPE_USIZE);
                }
            }
            if (node.child_0 == self.ptr_from_int_name_id) {
                var pfi_t: u32 = @intCast(u32, type_mod.TYPE_USIZE);
                var pfi_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
                if (pfi_rt) |prt| {
                    var pfi_ty = self.ctx.registry.types_items[@intCast(usize, prt)];
                    if (pfi_ty.kind == type_mod.TypeKind.ptr_type or pfi_ty.kind == type_mod.TypeKind.many_ptr_type) {
                        pfi_t = prt;
                    }
                }
                if (ec.len >= @intCast(usize, 1)) {
                    var pfi_arg = lowerExpr(self, ec[@intCast(usize, 0)]);
                    var pfi_res = nextTemp(self, pfi_t);
                    emitInst(self, LirInst{ .int_to_ptr = .{ .value = pfi_arg, .target = pfi_t, .result = pfi_res } });
                    return pfi_res;
                }
                return nextTemp(self, pfi_t);
            }
            if (node.child_0 == self.field_parent_ptr_name_id) {
                if (ec.len >= @intCast(usize, 3)) {
                    var fpp_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
                    var fpp_outer = type_resolver.resolveTypeExprFull(&fpp_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                    if (fpp_outer != type_mod.TYPE_UNDEFINED) {
                        var fpp_oty = self.ctx.registry.types_items[@intCast(usize, fpp_outer)];
                        if (fpp_oty.state == @intCast(u8, 2) and fpp_oty.kind == type_mod.TypeKind.struct_type) {
                            var fpp_fields: []type_mod.FieldEntry = undefined;
                            type_mod.typeRegistryGetStructFields(self.ctx.registry, fpp_outer, &fpp_fields);
                            var fpp_fnode = ast_mod.astStoreNodeAt(self.ctx.store, ec[@intCast(usize, 1)]);
                            if (fpp_fnode.kind == AstKind.string_literal) {
                                var fpp_sv = ast_mod.astStoreNodePayload(self.ctx.store, ec[@intCast(usize, 1)]);
                                var fpp_want = self.ctx.store.string_values.items[@intCast(usize, fpp_sv)];
                                var fpp_i: usize = 0;
                                while (fpp_i < fpp_fields.len) : (fpp_i += 1) {
                                    if (fpp_fields[fpp_i].name_id == fpp_want) {
                                        var fpp_off: u64 = @intCast(u64, fpp_fields[fpp_i].offset);
                                        var fpp_base = lowerExpr(self, ec[@intCast(usize, 2)]);
                                        var fpp_t1 = nextTemp(self, type_mod.TYPE_USIZE);
                                        emitInst(self, LirInst{ .ptr_to_int = .{ .value = fpp_base, .result = fpp_t1 } });
                                        var fpp_t2 = nextTemp(self, type_mod.TYPE_USIZE);
                                        emitInst(self, LirInst{ .int_const = .{ .value = fpp_off, .result = fpp_t2 } });
                                        var fpp_t3 = nextTemp(self, type_mod.TYPE_USIZE);
                                        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = fpp_t1, .rhs = fpp_t2, .result = fpp_t3 } });
                                        var fpp_ptr = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, fpp_outer, false);
                                        var fpp_res = nextTemp(self, fpp_ptr);
                                        emitInst(self, LirInst{ .int_to_ptr = .{ .value = fpp_t3, .target = fpp_ptr, .result = fpp_res } });
                                        return fpp_res;
                                    }
                                }
                            }
                        }
                    }
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.bitcast_name_id) {
                if (ec.len >= @intCast(usize, 2)) {
                    var bc_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
                    var bc_dst = type_resolver.resolveTypeExprFull(&bc_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                    if (bc_dst != type_mod.TYPE_UNDEFINED) {
                        var bc_arg = lowerExpr(self, ec[@intCast(usize, 1)]);
                        var bc_res = nextTemp(self, bc_dst);
                        emitInst(self, LirInst{ .int_cast = .{ .value = bc_arg, .target = bc_dst, .result = bc_res, .is_checked = @intCast(u8, 0) } });
                        return bc_res;
                    }
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node_idx)) |cv| {
                var fold_ty_box: [1]u32 = [1]u32{ type_mod.TYPE_USIZE };
                if (node.child_0 == self.intcast_name_id) {
                    var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
                    if (rt) |t| {
                        if (t != type_mod.TYPE_USIZE and t != type_mod.TYPE_UNDEFINED and t != type_mod.TYPE_INT_LIT) {
                            fold_ty_box[0] = t;
                        }
                    } else {
                        if (ec.len >= @intCast(usize, 1)) {
                            var ct_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
                            var ct = type_resolver.resolveTypeExprFull(&ct_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
                            if (ct != type_mod.TYPE_UNDEFINED) {
                                fold_ty_box[0] = ct;
                            }
                        }
                    }
                }
                if (node.child_0 == self.is_windows_name_id) {
                    fold_ty_box[0] = type_mod.TYPE_BOOL;
                }
                var cres = nextTemp(self, fold_ty_box[0]);
                emitInst(self, LirInst{ .int_const = .{ .value = cv, .result = cres } });
                var cm: []const u8 = "CEV\n"; pal.markerWrite(cm);
                return cres;
            }

            if (node.child_0 == self.size_of_name_id or node.child_0 == self.align_of_name_id or node.child_0 == self.offset_of_name_id or node.child_0 == self.bit_size_of_name_id or node.child_0 == self.bit_offset_of_name_id) {
                iceUnresolvedComptime(self, node_idx);
                return nextTemp(self, type_mod.TYPE_USIZE);
            }
            if (node.child_0 == self.enumtoint_name_id) {
                var bm: []const u8 = "E"; pal.markerWrite(bm);
                if (ec.len >= 1) {
                    return lowerExpr(self, ec[@intCast(usize, 0)]);
                } else { return nextTemp(self, type_mod.TYPE_VOID); }
            }
            if (node.child_0 == self.cvastart_name_id) {
                if (self.func.is_variadic == @intCast(u8, 0)) {
                    var va_msg: []const u8 = "@cVaStart used in a non-variadic function";
                    _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3012_VARARGS_INVALID)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), va_msg);
                    return nextTemp(self, type_mod.TYPE_VOID);
                }
                var vst: u32 = TEMP_NONE;
                if (ec.len >= @intCast(usize, 1)) {
                    vst = vaListArgTemp(self, ec[@intCast(usize, 0)]);
                }
                var vsp: u32 = TEMP_NONE;
                if (self.func.params.len > @intCast(usize, 0)) {
                    vsp = self.func.params.items[self.func.params.len - @intCast(usize, 1)].temp_id;
                }
                emitInst(self, LirInst{ .va_start = .{ .va_list_temp = vst, .last_param_temp = vsp } });
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.cvaarg_name_id) {
                if (ec.len >= @intCast(usize, 2)) {
                    var vat = vaListArgTemp(self, ec[@intCast(usize, 0)]);
                    var ct_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
                    var vatid = type_resolver.resolveTypeExprFull(&ct_env, ec[@intCast(usize, 1)], @intCast(u32, 0));
                    var vares = nextTemp(self, vatid);
                    emitInst(self, LirInst{ .va_arg = .{ .va_list_temp = vat, .type_id = vatid, .result = vares } });
                    return vares;
                } else {
                    return nextTemp(self, type_mod.TYPE_VOID);
                }
            }
            if (node.child_0 == self.cvaend_name_id) {
                var vet: u32 = TEMP_NONE;
                if (ec.len >= @intCast(usize, 1)) {
                    vet = vaListArgTemp(self, ec[@intCast(usize, 0)]);
                }
                emitInst(self, LirInst{ .va_end = .{ .va_list_temp = vet } });
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.putchar_name_id) {
                if (ec.len >= @intCast(usize, 1)) {
                    var pc_val = lowerExpr(self, ec[@intCast(usize, 0)]);
                    emitInst(self, LirInst{ .builtin_put_char = .{ .value = pc_val } });
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.stdout_write_name_id or node.child_0 == self.stderr_write_name_id) {
                if (ec.len >= @intCast(usize, 2)) {
                    var so_ptr = lowerExpr(self, ec[@intCast(usize, 0)]);
                    var so_len = lowerExpr(self, ec[@intCast(usize, 1)]);
                    if (node.child_0 == self.stdout_write_name_id) {
                        emitInst(self, LirInst{ .builtin_stdout_write = .{ .ptr = so_ptr, .len = so_len } });
                    } else {
                        emitInst(self, LirInst{ .builtin_stderr_write = .{ .ptr = so_ptr, .len = so_len } });
                    }
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.getchar_name_id) {
                var gc_res = nextTemp(self, type_mod.TYPE_U8);
                emitInst(self, LirInst{ .builtin_get_char = .{ .result = gc_res } });
                return gc_res;
            }
            if (node.child_0 == self.exit_name_id) {
                if (ec.len >= @intCast(usize, 1)) {
                    var ex_val = lowerExpr(self, ec[@intCast(usize, 0)]);
                    emitInst(self, LirInst{ .builtin_exit = .{ .value = ex_val } });
                }
                self.block_terminated = @intCast(u8, 1);
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.panic_name_id) {
                var pr_pt = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, type_mod.TYPE_C_CHAR, true);
                var pr_pref_s: []const u8 = "panic: ";
                var pr_pref_id = si_mod.stringInternerIntern(self.ctx.registry.interner, pr_pref_s);
                var pr_pref_t = nextTemp(self, pr_pt);
                emitInst(self, LirInst{ .string_const = .{ .string_id = pr_pref_id, .result = pr_pref_t } });
                var pr_pref_l = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 7), .result = pr_pref_l } });
                emitInst(self, LirInst{ .builtin_stderr_write = .{ .ptr = pr_pref_t, .len = pr_pref_l } });
                if (ec.len >= @intCast(usize, 1)) {
                    var pr_node = ast_mod.astStoreNodeAt(self.ctx.store, ec[@intCast(usize, 0)]);
                    if (pr_node.kind == AstKind.string_literal) {
                        var pr_sid: u32 = ast_mod.astStoreNodePayload(self.ctx.store, ec[@intCast(usize, 0)]);
                        if (@intCast(usize, ast_mod.astStoreNodePayload(self.ctx.store, ec[@intCast(usize, 0)])) < self.ctx.store.string_values.len) { pr_sid = self.ctx.store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(self.ctx.store, ec[@intCast(usize, 0)]))]; }
                        var pr_str = si_mod.stringInternerGet(self.ctx.registry.interner, pr_sid);
                        var pr_mt = nextTemp(self, pr_pt);
                        emitInst(self, LirInst{ .string_const = .{ .string_id = pr_sid, .result = pr_mt } });
                        var pr_ml = nextTemp(self, type_mod.TYPE_U32);
                        emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, pr_str.len), .result = pr_ml } });
                        emitInst(self, LirInst{ .builtin_stderr_write = .{ .ptr = pr_mt, .len = pr_ml } });
                    } else {
                        var pr_val = lowerExpr(self, ec[@intCast(usize, 0)]);
                        var pr_vt = getTempType(self, pr_val);
                        if (@intCast(usize, pr_vt) < self.ctx.registry.types_len and self.ctx.registry.types_items[@intCast(usize, pr_vt)].kind == type_mod.TypeKind.slice_type) {
                            var pr_ptr = nextTemp(self, pr_pt);
                            emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = pr_val, .field_id = type_mod.SLICE_FIELD_PTR, .result = pr_ptr } });
                            var pr_len = nextTemp(self, type_mod.TYPE_USIZE);
                            emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = pr_val, .field_id = type_mod.SLICE_FIELD_LEN, .result = pr_len } });
                            emitInst(self, LirInst{ .builtin_stderr_write = .{ .ptr = pr_ptr, .len = pr_len } });
                        }
                    }
                }
                var pr_nl_s: []const u8 = "\n";
                var pr_nl_id = si_mod.stringInternerIntern(self.ctx.registry.interner, pr_nl_s);
                var pr_nl_t = nextTemp(self, pr_pt);
                emitInst(self, LirInst{ .string_const = .{ .string_id = pr_nl_id, .result = pr_nl_t } });
                var pr_nl_l = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 1), .result = pr_nl_l } });
                emitInst(self, LirInst{ .builtin_stderr_write = .{ .ptr = pr_nl_t, .len = pr_nl_l } });
                emitInst(self, LirInst{ .trap = {} });
                self.block_terminated = @intCast(u8, 1);
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.sleep_ms_name_id) {
                if (ec.len >= @intCast(usize, 1)) {
                    var sm_val = lowerExpr(self, ec[@intCast(usize, 0)]);
                    emitInst(self, LirInst{ .builtin_sleep_ms = .{ .value = sm_val } });
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.console_clear_name_id) {
                emitInst(self, LirInst{ .builtin_console_clear = .{} });
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.console_gotoxy_name_id) {
                if (ec.len >= @intCast(usize, 2)) {
                    var cgx = lowerExpr(self, ec[@intCast(usize, 0)]);
                    var cgy = lowerExpr(self, ec[@intCast(usize, 1)]);
                    emitInst(self, LirInst{ .builtin_console_gotoxy = .{ .x = cgx, .y = cgy } });
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (node.child_0 == self.console_set_color_name_id) {
                if (ec.len >= @intCast(usize, 2)) {
                    var csf = lowerExpr(self, ec[@intCast(usize, 0)]);
                    var csb = lowerExpr(self, ec[@intCast(usize, 1)]);
                    emitInst(self, LirInst{ .builtin_console_set_color = .{ .fg = csf, .bg = csb } });
                }
                return nextTemp(self, type_mod.TYPE_VOID);
            }
            if (ec.len >= 2) {
                var elm: []const u8 = "B"; pal.markerWrite(elm);
                if (node.child_0 == self.intcast_name_id) { var bm: []const u8 = "I"; pal.markerWrite(bm); }
                else if (node.child_0 == self.ptrcast_name_id) { var bm: []const u8 = "P"; pal.markerWrite(bm); }
                else { var bm: []const u8 = "F"; pal.markerWrite(bm); }
                var val_temp = lowerExpr(self, ec[@intCast(usize, 1)]);
        var ty_node = ast_mod.astStoreNodeAt(store, ec[@intCast(usize, 0)]);
        t_target = type_mod.TYPE_U32;
        if (ty_node.kind == AstKind.fn_type) {
            var fc_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
            var fc_t = type_resolver.resolveTypeExprFull(&fc_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
            if (fc_t != type_mod.TYPE_UNDEFINED) {
                t_target = fc_t;
                var fc_inner = self.ctx.registry.types_items[@intCast(usize, fc_t)];
                if (fc_inner.kind == type_mod.TypeKind.ptr_type) {
                    var fc_pp = self.ctx.registry.ptr_items[@intCast(usize, fc_inner.payload_idx)];
                    type_mod.typeRegistryMarkFnPtrUsed(self.ctx.registry, fc_pp.base);
                } else {
                    type_mod.typeRegistryMarkFnPtrUsed(self.ctx.registry, fc_t);
                }
                var fcm: []const u8 = "FNT:t"; pal.markerWrite(fcm);
            }
        } else {
            var ct_env = type_resolver.TypeResolveEnv{ .store = self.ctx.store, .typereg = self.ctx.registry, .symbol_reg = self.ctx.symbol_tables, .interner = self.ctx.registry.interner, .module_id = self.module_id };
            var ct = type_resolver.resolveTypeExprFull(&ct_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
            if (ct != type_mod.TYPE_UNDEFINED) { t_target = ct; }
        }
        if (t_target == type_mod.TYPE_U32) { var cdm: []const u8 = "CASTDFLT:n"; pal.markerWriteInt(cdm, node_idx); var cdk: []const u8 = "CASTDFLT:k"; pal.markerWriteInt(cdk, @intCast(u32, @enumToInt(ty_node.kind))); }
        var result = nextTemp(self, t_target);
        if (node.child_0 == self.intcast_name_id) {
            var src_ty = getTempType(self, val_temp);
            var src_bits = intCastTypeBits(self.ctx.registry, src_ty);
            var dst_bits = intCastTypeBits(self.ctx.registry, t_target);
            var chk: u8 = @intCast(u8, 0);
            if (self.ctx.safe_checks and src_bits > @intCast(u32, 0) and dst_bits > @intCast(u32, 0)) {
                if (src_bits > dst_bits) {
                    chk = @intCast(u8, 1);
                } else if (src_bits == dst_bits) {
                    var src_s = intCastTypeIsSigned(self.ctx.registry, src_ty);
                    var dst_s = intCastTypeIsSigned(self.ctx.registry, t_target);
                    if (src_s != dst_s) { chk = @intCast(u8, 1); }
                }
            }
            emitInst(self, LirInst{ .int_cast = .{
                .value = val_temp, .target = t_target, .result = result,
                 .is_checked = chk,
            } });
        } else if (node.child_0 == self.inttofloat_name_id) {
            emitInst(self, LirInst{ .int_to_float = .{
                .value = val_temp, .target = t_target, .result = result,
            } });
        } else if (node.child_0 == self.ptrcast_name_id) {
            emitInst(self, LirInst{ .ptr_cast = .{
                .value = val_temp, .target = t_target, .result = result,
            } });
        } else if (node.child_0 == self.inttoptr_name_id) {
            emitInst(self, LirInst{ .int_to_ptr = .{
                .value = val_temp, .target = t_target, .result = result,
            } });
        } else if (node.child_0 == self.inttoenum_name_id) {
            emitInst(self, LirInst{ .int_cast = .{
                .value = val_temp, .target = t_target, .result = result,
                .is_checked = @intCast(u8, 0),
            } });
        } else if (node.child_0 == self.as_name_id) {
            emitInst(self, LirInst{ .int_cast = .{
                .value = val_temp, .target = t_target, .result = result,
                .is_checked = @intCast(u8, 0),
            } });
        }
        return result;
            }
            return nextTemp(self, type_mod.TYPE_VOID);
    } else if (node.kind == AstKind.try_expr) {
        var inner_temp = lowerExpr(self, node.child_0);
        var eu_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
        {
            var eu_type = getTempType(self, inner_temp);
            if (eu_type != type_mod.TYPE_UNDEFINED) {
                var ty = self.ctx.registry.types_items[@intCast(usize, eu_type)];
                if (ty.kind == type_mod.TypeKind.error_union_type) {
                    eu_box[0] = eu_type;
                }
            }
        }
        if (eu_box[0] != type_mod.TYPE_UNDEFINED) {
            var is_err_temp = nextTemp(self, type_mod.TYPE_U8);
            emitInst(self, LirInst{ .check_error = .{ .value = inner_temp, .result = is_err_temp } });
            var err_bb = createBlock(self);
            var ok_bb = createBlock(self);
            var join_bb = createBlock(self);
            emitInst(self, LirInst{ .branch = .{ .cond = is_err_temp, .then_bb = err_bb, .else_bb = ok_bb } });
            self.current_bb = err_bb;
            expandDefers(self, @intCast(u32, 0), @intCast(u8, 1), @intCast(u8, 0));
            var do_rewrap: u8 = @intCast(u8, 0);
            {
                var rt = self.func.return_type;
                if (rt != type_mod.TYPE_UNDEFINED) {
                    if (rt != eu_box[0]) {
                        var rtt = self.ctx.registry.types_items[@intCast(usize, rt)];
                        if (rtt.kind == type_mod.TypeKind.error_union_type) {
                            do_rewrap = @intCast(u8, 1);
                        }
                    }
                }
            }
            if (do_rewrap != @intCast(u8, 0)) {
                var prop_code = nextTemp(self, type_mod.TYPE_I32);
                emitInst(self, LirInst{ .unwrap_error_code = .{ .value = inner_temp, .result = prop_code } });
                var prop_rewrapped = nextTemp(self, self.func.return_type);
                emitInst(self, LirInst{ .wrap_error_err = .{ .value = prop_code, .result = prop_rewrapped, .type_id = self.func.return_type } });
                emitInst(self, LirInst{ .ret = prop_rewrapped });
            } else {
                emitInst(self, LirInst{ .ret = inner_temp });
            }
            self.block_terminated = @intCast(u8, 1);
            self.current_bb = ok_bb;
            self.block_terminated = @intCast(u8, 0);
            var result = nextTemp(self, euPayloadOf(self, eu_box[0]));
            emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = inner_temp, .result = result } });
            if (self.block_terminated == @intCast(u8, 0)) {
                emitInst(self, LirInst{ .jump = join_bb });
            }
            self.current_bb = join_bb;
            return result;
        } else {
            return inner_temp;
        }
    } else if (node.kind == AstKind.catch_expr) {
        var lhs_temp = lowerExpr(self, node.child_0);
        var eu_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
        {
            var eu_type_catch = getTempType(self, lhs_temp);
            if (eu_type_catch != type_mod.TYPE_UNDEFINED) {
                var ty_c = self.ctx.registry.types_items[@intCast(usize, eu_type_catch)];
                if (ty_c.kind == type_mod.TypeKind.error_union_type) {
                    eu_box[0] = eu_type_catch;
                }
            }
        }
        if (eu_box[0] != type_mod.TYPE_UNDEFINED) {
            var is_err_temp = nextTemp(self, type_mod.TYPE_U8);
            emitInst(self, LirInst{ .check_error = .{ .value = lhs_temp, .result = is_err_temp } });
            var err_bb = createBlock(self);
            var ok_bb = createBlock(self);
            var join_bb = createBlock(self);
            emitInst(self, LirInst{ .branch = .{ .cond = is_err_temp, .then_bb = err_bb, .else_bb = ok_bb } });
            var join_temp = nextTemp(self, euPayloadOf(self, eu_box[0]));
            var cdiag_pt: u32 = euPayloadOf(self, eu_box[0]);
            var cdiag_p1: []const u8 = "CDIAG:pay"; pal.markerWriteInt(cdiag_p1, cdiag_pt);
            self.current_bb = err_bb;
            self.block_terminated = @intCast(u8, 0);
            var cex_n2_m: []const u8 = "CEX:n2"; pal.markerWrite(cex_n2_m); var cex_n2_b: [10]u8 = undefined; var cex_n2_l = itoa_mod.itoa(node.child_2, cex_n2_b[0..]); var cex_n2_s: usize = @intCast(usize, 9) - @intCast(usize, cex_n2_l); pal.markerWrite(cex_n2_b[cex_n2_s..@intCast(usize, 9)]); var cex_n2_nl: []const u8 = "\n"; pal.markerWrite(cex_n2_nl);
            if (node.child_2 != 0) {
                var cex_c2_m: []const u8 = "CEX:c2"; pal.markerWrite(cex_c2_m); var cex_c2_b: [10]u8 = undefined; var cex_c2_l = itoa_mod.itoa(node.child_2, cex_c2_b[0..]); var cex_c2_s: usize = @intCast(usize, 9) - @intCast(usize, cex_c2_l); pal.markerWrite(cex_c2_b[cex_c2_s..@intCast(usize, 9)]); var cex_c2_nl: []const u8 = "\n"; pal.markerWrite(cex_c2_nl);
                var capture_node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_2);
                var err_code_temp = nextTemp(self, type_mod.TYPE_I32);
                emitInst(self, LirInst{ .unwrap_error_code = .{ .value = lhs_temp, .result = err_code_temp } });
                var catch_cap_name = maybeDisambiguateCapture(self, ast_mod.astStoreNodePayload(self.ctx.store, node.child_2), type_mod.TYPE_I32);
                addLocalDecl(self, catch_cap_name, type_mod.TYPE_I32, err_code_temp, self.scope_depth, @intCast(u8, 1));
                emitInst(self, LirInst{ .decl_local = .{ .name_id = catch_cap_name, .type_id = type_mod.TYPE_I32, .temp = err_code_temp } });
                var decl_m: []const u8 = "DECL:t"; pal.markerWrite(decl_m); var decl_b: [10]u8 = undefined; var decl_l = itoa_mod.itoa(err_code_temp, decl_b[0..]); var decl_s: usize = @intCast(usize, 9) - @intCast(usize, decl_l); pal.markerWrite(decl_b[decl_s..@intCast(usize, 9)]); var decl_bb: []const u8 = "b"; pal.markerWrite(decl_bb); var decl_bb_b: [10]u8 = undefined; var decl_bb_l = itoa_mod.itoa(@intCast(u32, self.current_bb), decl_bb_b[0..]); var decl_bb_s: usize = @intCast(usize, 9) - @intCast(usize, decl_bb_l); pal.markerWrite(decl_bb_b[decl_bb_s..@intCast(usize, 9)]); var decl_nl: []const u8 = "\n"; pal.markerWrite(decl_nl);
            }
            self.capture_shadow.count = @intCast(usize, 0);
            var err_val = lowerExprOrBlock(self, node.child_1);
            var cdiag_et: u32 = getTempType(self, err_val);
            var cdiag_e1: []const u8 = "CDIAG:errT"; pal.markerWriteInt(cdiag_e1, cdiag_et);
            var cdiag_ek: u32 = @intCast(u32, 0); if (@intCast(usize, cdiag_et) < self.ctx.registry.types_len) { cdiag_ek = @intCast(u32, @enumToInt(self.ctx.registry.types_items[@intCast(usize, cdiag_et)].kind)); }
            var cdiag_e2: []const u8 = "CDIAG:errK"; pal.markerWriteInt(cdiag_e2, cdiag_ek);
            var cex1_m: []const u8 = "CEX:c1"; pal.markerWrite(cex1_m); var cex1_b: [10]u8 = undefined; var cex1_l = itoa_mod.itoa(node.child_1, cex1_b[0..]); var cex1_s: usize = @intCast(usize, 9) - @intCast(usize, cex1_l); pal.markerWrite(cex1_b[cex1_s..@intCast(usize, 9)]); var cex1_nl: []const u8 = "\n"; pal.markerWrite(cex1_nl);
            var cexk_m: []const u8 = "CEX:ck"; pal.markerWrite(cexk_m); var cexk_b: [10]u8 = undefined; var ck_val: u32 = @intCast(u32, 0); if (node.child_1 != @intCast(u32, 0)) { var c1node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_1); ck_val = @intCast(u32, @enumToInt(c1node.kind)); } var cexk_l = itoa_mod.itoa(ck_val, cexk_b[0..]); var cexk_s: usize = @intCast(usize, 9) - @intCast(usize, cexk_l); pal.markerWrite(cexk_b[cexk_s..@intCast(usize, 9)]); var cexk_nl: []const u8 = "\n"; pal.markerWrite(cexk_nl);
            var cexv_m: []const u8 = "CEX:ev"; pal.markerWrite(cexv_m); var cexv_b: [10]u8 = undefined; var cexv_l = itoa_mod.itoa(err_val, cexv_b[0..]); var cexv_s: usize = @intCast(usize, 9) - @intCast(usize, cexv_l); pal.markerWrite(cexv_b[cexv_s..@intCast(usize, 9)]); var cexv_nl: []const u8 = "\n"; pal.markerWrite(cexv_nl);
            var cexb_m: []const u8 = "CEX:bt"; pal.markerWrite(cexb_m); var cexb_b: [10]u8 = undefined; var cexb_l = itoa_mod.itoa(@intCast(u32, self.block_terminated), cexb_b[0..]); var cexb_s: usize = @intCast(usize, 9) - @intCast(usize, cexb_l); pal.markerWrite(cexb_b[cexb_s..@intCast(usize, 9)]); var cexb_nl: []const u8 = "\n"; pal.markerWrite(cexb_nl);
            var cexg_m: []const u8 = "CEX:g"; pal.markerWrite(cexg_m); var cexg_b: [10]u8 = undefined; var cexg_l = itoa_mod.itoa(@intCast(u32, self.block_terminated), cexg_b[0..]); var cexg_s: usize = @intCast(usize, 9) - @intCast(usize, cexg_l); pal.markerWrite(cexg_b[cexg_s..@intCast(usize, 9)]); var cexg_nl: []const u8 = "\n"; pal.markerWrite(cexg_nl);
            if (self.block_terminated == @intCast(u8, 0)) {
                var hit_m: []const u8 = "CEX:HIT\n"; pal.markerWrite(hit_m);
                err_val = materializeInto(self, err_val, euPayloadOf(self, eu_box[0]), srcIntentForNode(self, node.child_1));
                emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = join_temp, .src = err_val } });
                emitInst(self, LirInst{ .jump = join_bb });
            }
            self.block_terminated = @intCast(u8, 0);
            self.current_bb = ok_bb;
            var ok_val = nextTemp(self, euPayloadOf(self, eu_box[0]));
            emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = lhs_temp, .result = ok_val } });
            var cdiag_ot: u32 = getTempType(self, ok_val);
            var cdiag_o1: []const u8 = "CDIAG:okT"; pal.markerWriteInt(cdiag_o1, cdiag_ot);
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = join_temp, .src = ok_val } });
            if (self.block_terminated == @intCast(u8, 0)) {
                emitInst(self, LirInst{ .jump = join_bb });
            }
            self.current_bb = join_bb;
            return join_temp;
        } else {
            return lhs_temp;
        }
    } else if (node.kind == AstKind.orelse_expr) {
        var lhs_temp = lowerExpr(self, node.child_0);
        var optvc_m: []const u8 = "OPTVOID:lhs"; pal.markerWriteInt(optvc_m, lhs_temp);
        var has_val_temp = nextTemp(self, type_mod.TYPE_U8);
        emitInst(self, LirInst{ .check_optional = .{ .value = lhs_temp, .result = has_val_temp } });
        var null_bb = createBlock(self);
        var ok_bb = createBlock(self);
        var join_bb = createBlock(self);
        emitInst(self, LirInst{ .branch = .{ .cond = has_val_temp, .then_bb = ok_bb, .else_bb = null_bb } });
        var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var join_temp = nextTemp(self, if (rt) |t| t else type_mod.TYPE_UNDEFINED);
        var omg_j_m: []const u8 = "OMG:joinT"; pal.markerWriteInt(omg_j_m, join_temp);
        var omg_nv_m: []const u8 = "OMG:JUNDEF\n"; pal.markerWrite(omg_nv_m);
        var und_oej_m: []const u8 = "UND:oeJt"; pal.markerWrite(und_oej_m);
        var und_oej_tb: [10]u8 = undefined; var und_oej_tl = itoa_mod.itoa(join_temp, und_oej_tb[0..]); var und_oej_ts: usize = @intCast(usize, 9) - @intCast(usize, und_oej_tl); pal.markerWrite(und_oej_tb[und_oej_ts..@intCast(usize, 9)]);
        var und_oej_nl: []const u8 = "\n"; pal.markerWrite(und_oej_nl);
        self.current_bb = null_bb;
        var oe_nd = ast_mod.astStoreNodeAt(self.ctx.store, node.child_1);
        if (oe_nd.kind == AstKind.return_stmt or oe_nd.kind == AstKind.break_stmt or oe_nd.kind == AstKind.continue_stmt) {
            lowerStmt(self, node.child_1);
        } else {
            var null_val = lowerExpr(self, node.child_1);
            var oe_an = ast_mod.astStoreNodeAt(self.ctx.store, node.child_1);
            if (self.block_terminated == @intCast(u8, 0)) {
                var oe_int: SrcIntent = SrcIntent.value;
                if (oe_an.kind == AstKind.null_literal) { oe_int = SrcIntent.null_src; }
                if (oe_an.kind == AstKind.error_literal) { oe_int = SrcIntent.error_src; }
                null_val = materializeInto(self, null_val, if (rt) |t| t else type_mod.TYPE_UNDEFINED, oe_int);
                emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = join_temp, .src = null_val } });
            }
        }
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.block_terminated = @intCast(u8, 0);
        self.current_bb = ok_bb;
        var rt2 = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ok_val = nextTemp(self, if (rt2) |t| t else type_mod.TYPE_UNDEFINED);
        emitInst(self, LirInst{ .unwrap_optional = .{ .value = lhs_temp, .result = ok_val } });
        emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = join_temp, .src = ok_val } });
        var omg_k_m: []const u8 = "OMG:okT"; pal.markerWriteInt(omg_k_m, ok_val);
        var omg_ku_m: []const u8 = "OMG:KUNDEF\n"; pal.markerWrite(omg_ku_m);
        var und_oek_m: []const u8 = "UND:oeKt"; pal.markerWrite(und_oek_m);
        var und_oek_tb: [10]u8 = undefined; var und_oek_tl = itoa_mod.itoa(ok_val, und_oek_tb[0..]); var und_oek_ts: usize = @intCast(usize, 9) - @intCast(usize, und_oek_tl); pal.markerWrite(und_oek_tb[und_oek_ts..@intCast(usize, 9)]);
        var und_oek_nl: []const u8 = "\n"; pal.markerWrite(und_oek_nl);
        var omg_ok_m: []const u8 = "OMG:okAsgJ"; pal.markerWriteInt(omg_ok_m, join_temp);
        var omg_oks_m: []const u8 = "OMG:okSrc"; pal.markerWriteInt(omg_oks_m, ok_val);
        var omg_oknl_m: []const u8 = "\n"; pal.markerWrite(omg_oknl_m);
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        return join_temp;
    } else if (node.kind == AstKind.if_expr) {
        var ie_rt3 = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ie_rtype3: u32 = if (ie_rt3) |t| t else type_mod.TYPE_UNDEFINED;
        var ie_fold = hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node.child_0);
        // C3: if_expr comptime-fold sub-path is capture-free by construction (a capture
        // requires an optional cond, which comptime_values never folds — scalars/bools
        // only); guard on payload==0 to mirror the if_stmt fold guard defensively.
        if (ie_fold) |ie_fv| {
            if (ast_mod.astStoreNodePayload(store, node_idx) == @intCast(u32, 0)) {
                var ie_res = nextTemp(self, ie_rtype3);
                if (ie_fv != @intCast(u64, 0)) {
                    var ie_then = lowerExpr(self, node.child_1);
                    ie_then = materializeInto(self, ie_then, ie_rtype3, srcIntentForNode(self, node.child_1));
                    emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = ie_res, .src = ie_then } });
                } else {
                    var ie_else = lowerExpr(self, node.child_2);
                    ie_else = materializeInto(self, ie_else, ie_rtype3, srcIntentForNode(self, node.child_2));
                    emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = ie_res, .src = ie_else } });
                }
                return ie_res;
            }
        }
        var cond_temp = lowerExpr(self, node.child_0);
        var orig_cond_temp = cond_temp;
        if (@intCast(usize, cond_temp) < self.hoisted_temps.len) {
            var cond_t = getTempType(self, cond_temp);
            if (cond_t != type_mod.TYPE_UNDEFINED) {
                var cond_ty = self.ctx.registry.types_items[@intCast(usize, cond_t)];
                if (cond_ty.kind == type_mod.TypeKind.optional_type) {
                    var has_val = nextTemp(self, type_mod.TYPE_U8);
                    emitInst(self, LirInst{ .check_optional = .{ .value = cond_temp, .result = has_val } });
                    cond_temp = has_val;
                }
            }
        }
        var rt3 = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var ie_rtype: u32 = if (rt3) |t| t else type_mod.TYPE_UNDEFINED;
        var result = nextTemp(self, ie_rtype);
        var und_ie_m: []const u8 = "UND:ieRt"; pal.markerWrite(und_ie_m);
        var und_ie_tb: [10]u8 = undefined; var und_ie_tl = itoa_mod.itoa(result, und_ie_tb[0..]); var und_ie_ts: usize = @intCast(usize, 9) - @intCast(usize, und_ie_tl); pal.markerWrite(und_ie_tb[und_ie_ts..@intCast(usize, 9)]);
        var und_ie_nl: []const u8 = "\n"; pal.markerWrite(und_ie_nl);
        var then_bb = createBlock(self);
        var else_bb = createBlock(self);
        var join_bb = createBlock(self);
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = then_bb, .else_bb = else_bb } });
        self.current_bb = then_bb;
        if (ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
            var icap_idx = ast_mod.astStoreNodePayload(store, node_idx);
            var icapn = ast_mod.astStoreNodeAt(self.ctx.store, icap_idx);
            if (icapn.kind == AstKind.if_capture) {
                bindOptionalCapture(self, icap_idx, orig_cond_temp);
            }
        }
        pushScopeDepth(self);
        var then_val = lowerExpr(self, node.child_1);
        if (self.block_terminated == @intCast(u8, 0)) {
            then_val = materializeInto(self, then_val, ie_rtype, srcIntentForNode(self, node.child_1));
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = result, .src = then_val } });
        }
        popScopeDepth(self);
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = else_bb;
        self.block_terminated = @intCast(u8, 0);
        var else_val = lowerExpr(self, node.child_2);
        if (self.block_terminated == @intCast(u8, 0)) {
            else_val = materializeInto(self, else_val, ie_rtype, srcIntentForNode(self, node.child_2));
            emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = result, .src = else_val } });
        }
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = join_bb });
        }
        self.current_bb = join_bb;
        self.block_terminated = @intCast(u8, 0);
        self.capture_shadow.count = @intCast(usize, 0);
        return result;
      } else if (node.kind == AstKind.array_init) {
         var ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
         var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
         var arr_tid: u32 = if (rt) |it| it else @intCast(u32, 0);
         if (arr_tid == @intCast(u32, 0)) {
             var aelem: u32 = if (ec.len > @intCast(usize, 0)) if (ast_mod.astStoreNodeAt(store, ec[@intCast(usize, 0)]).kind == AstKind.char_literal) type_mod.TYPE_U8 else type_mod.TYPE_U32 else type_mod.TYPE_U32;
               arr_tid = type_mod.typeRegistryGetOrCreateArray(self.ctx.registry, aelem, @intCast(u32, ec.len));
           }
           var elem_t: u32 = arr_tid;
           var aty = self.ctx.registry.types_items[@intCast(usize, arr_tid)];
           if (@enumToInt(aty.kind) == @intCast(u32, @enumToInt(type_mod.TypeKind.array_type))) {
               var ap = self.ctx.registry.array_items[@intCast(usize, aty.payload_idx)];
               elem_t = ap.elem;
           }
           var bei: usize = @intCast(usize, 0);
           while (bei < ec.len) : (bei += @intCast(usize, 1)) {
               var cn = ast_mod.astStoreNodeAt(store, ec[bei]);
               if (cn.kind == AstKind.struct_init) {
                   var exi = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, ec[bei]);
                   if (exi == null) { resolved_mod.resolvedTypeTableSet(self.ctx.resolved_types, ec[bei], elem_t); }
               }
           }
           var base_temp = nextTemp(self, arr_tid);
        var ei: usize = @intCast(usize, 0);
        while (ei < ec.len) : (ei += @intCast(usize, 1)) {
            var val_temp = lowerExpr(self, ec[ei]);
            var ix_temp = nextTemp(self, type_mod.TYPE_U32);
            emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, ei), .result = ix_temp } });
            emitInst(self, LirInst{ .assign_index = .{ .name_id = @intCast(u32, 0), .base = base_temp, .index = ix_temp, .src = val_temp } });
        }
        return base_temp;
    } else if (node.kind == AstKind.struct_init) {
        var init_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var base_temp = nextTemp(self, if (init_type) |it| it else type_mod.TYPE_UNDEFINED);
        if (init_type == null) {
            var und_si_m: []const u8 = "UND:siBt"; pal.markerWrite(und_si_m);
            var und_si_tb: [10]u8 = undefined; var und_si_tl = itoa_mod.itoa(base_temp, und_si_tb[0..]); var und_si_ts: usize = @intCast(usize, 9) - @intCast(usize, und_si_tl); pal.markerWrite(und_si_tb[und_si_ts..@intCast(usize, 9)]);
            var und_si_nl: []const u8 = "\n"; pal.markerWrite(und_si_nl);
        }
        var sin2_m: []const u8 = "SIN2:n"; pal.markerWrite(sin2_m);
        var sin2_nb: [10]u8 = undefined; var sin2_nl = itoa_mod.itoa(node_idx, sin2_nb[0..]); var sin2_ns: usize = @intCast(usize, 9) - @intCast(usize, sin2_nl); pal.markerWrite(sin2_nb[sin2_ns..@intCast(usize, 9)]);
        var sin2_bm: []const u8 = "b"; pal.markerWrite(sin2_bm);
        var sin2_bb: [10]u8 = undefined; var sin2_bl = itoa_mod.itoa(base_temp, sin2_bb[0..]); var sin2_bs: usize = @intCast(usize, 9) - @intCast(usize, sin2_bl); pal.markerWrite(sin2_bb[sin2_bs..@intCast(usize, 9)]);
        if (init_type) |it2| {
            var sin2_rm: []const u8 = "R"; pal.markerWrite(sin2_rm);
            var sin2_rb: [10]u8 = undefined; var sin2_rl = itoa_mod.itoa(it2, sin2_rb[0..]); var sin2_rs: usize = @intCast(usize, 9) - @intCast(usize, sin2_rl); pal.markerWrite(sin2_rb[sin2_rs..@intCast(usize, 9)]);
        } else {
            var sin2_mm: []const u8 = "M"; pal.markerWrite(sin2_mm);
        }
        var sin2_nl3: []const u8 = "\n"; pal.markerWrite(sin2_nl3);
        var ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
        var ei: usize = @intCast(usize, 0);
        while (ei < ec.len) : (ei += @intCast(usize, 1)) {
             var fi_node = ast_mod.astStoreNodeAt(store, ec[ei]);
            var vfi_m: []const u8 = "VFI:n"; pal.markerWrite(vfi_m);
            var vfi_nb: [10]u8 = undefined; var vfi_nl = itoa_mod.itoa(node_idx, vfi_nb[0..]); var vfi_ns: usize = @intCast(usize, 9) - @intCast(usize, vfi_nl); pal.markerWrite(vfi_nb[vfi_ns..@intCast(usize, 9)]);
            var vfi_0m: []const u8 = "0"; pal.markerWrite(vfi_0m);
            var vfi_0b: [10]u8 = undefined; var vfi_0l = itoa_mod.itoa(fi_node.child_0, vfi_0b[0..]); var vfi_0s: usize = @intCast(usize, 9) - @intCast(usize, vfi_0l); pal.markerWrite(vfi_0b[vfi_0s..@intCast(usize, 9)]);
            var vfi_cm: []const u8 = "c"; pal.markerWrite(vfi_cm);
            var vfi_cb: [10]u8 = undefined; var vfi_cl = itoa_mod.itoa(fi_node.child_1, vfi_cb[0..]); var vfi_cs: usize = @intCast(usize, 9) - @intCast(usize, vfi_cl); pal.markerWrite(vfi_cb[vfi_cs..@intCast(usize, 9)]);
            var vfi_em: []const u8 = "e"; pal.markerWrite(vfi_em);
            var vfi_eb: [10]u8 = undefined; var vfi_el = itoa_mod.itoa(@intCast(u32, ei), vfi_eb[0..]); var vfi_es: usize = @intCast(usize, 9) - @intCast(usize, vfi_el); pal.markerWrite(vfi_eb[vfi_es..@intCast(usize, 9)]);
            var vfi_nl2: []const u8 = "\n"; pal.markerWrite(vfi_nl2);
            var fi_name_id: u32 = ast_mod.astStoreNodePayload(store, ec[ei]);
            var sti_m: []const u8 = "STI:t"; pal.markerWrite(sti_m);
            var sti_tb: [10]u8 = undefined; var sti_tl = itoa_mod.itoa(self.temp_counter, sti_tb[0..]); var sti_ts: usize = @intCast(usize, 9) - @intCast(usize, sti_tl); pal.markerWrite(sti_tb[sti_ts..@intCast(usize, 9)]);
            var sti_em: []const u8 = "e"; pal.markerWrite(sti_em);
            var sti_eb: [10]u8 = undefined; var sti_el = itoa_mod.itoa(@intCast(u32, ei), sti_eb[0..]); var sti_es: usize = @intCast(usize, 9) - @intCast(usize, sti_el); pal.markerWrite(sti_eb[sti_es..@intCast(usize, 9)]);
            var sti_nm: []const u8 = "n"; pal.markerWrite(sti_nm);
            var sti_nb: [10]u8 = undefined; var sti_nl = itoa_mod.itoa(node_idx, sti_nb[0..]); var sti_ns: usize = @intCast(usize, 9) - @intCast(usize, sti_nl); pal.markerWrite(sti_nb[sti_ns..@intCast(usize, 9)]);
            var sti_nl2: []const u8 = "\n"; pal.markerWrite(sti_nl2);
            var is_undef_arr_field: bool = false;
            if (fi_node.child_0 != @intCast(u32, 0)) {
                var ua_c0 = ast_mod.astStoreNodeAt(store, fi_node.child_0);
                if (ua_c0.kind == AstKind.undefined_literal) {
                    if (init_type) |ua_it| {
                        var ua_ts = self.ctx.registry.types_items[@intCast(usize, ua_it)];
                        if (ua_ts.kind == type_mod.TypeKind.struct_type) {
                            var ua_sp = self.ctx.registry.st_items[@intCast(usize, ua_ts.payload_idx)];
                            var ua_fs: usize = @intCast(usize, ua_sp.fields_start);
                            var ua_fc: usize = @intCast(usize, ua_sp.fields_count);
                            var ua_fj: usize = @intCast(usize, 0);
                            while (ua_fj < ua_fc) : (ua_fj += @intCast(usize, 1)) {
                                if (self.ctx.registry.fe_items[ua_fs + ua_fj].name_id == fi_name_id) {
                                    var ua_ft = self.ctx.registry.types_items[@intCast(usize, self.ctx.registry.fe_items[ua_fs + ua_fj].type_id)];
                                    if (ua_ft.kind == type_mod.TypeKind.array_type) is_undef_arr_field = true;
                                    break;
                                }
                            }
                        } else if (ua_ts.kind == type_mod.TypeKind.tagged_union_type) {
                            var ua_tp = self.ctx.registry.tu_items[@intCast(usize, ua_ts.payload_idx)];
                            var ua_fs2: usize = @intCast(usize, ua_tp.fields_start);
                            var ua_fc2: usize = @intCast(usize, ua_tp.fields_count);
                            var ua_fj2: usize = @intCast(usize, 0);
                            while (ua_fj2 < ua_fc2) : (ua_fj2 += @intCast(usize, 1)) {
                                if (self.ctx.registry.fe_items[ua_fs2 + ua_fj2].name_id == fi_name_id) {
                                    var ua_ft2 = self.ctx.registry.types_items[@intCast(usize, self.ctx.registry.fe_items[ua_fs2 + ua_fj2].type_id)];
                                    if (ua_ft2.kind == type_mod.TypeKind.array_type) is_undef_arr_field = true;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            var val_temp: u32 = @intCast(u32, 0);
            if (!is_undef_arr_field) {
                if (fi_node.child_0 != @intCast(u32, 0)) {
                    val_temp = lowerExpr(self, fi_node.child_0);
                }
            }
            if (init_type) |it| {
                var ts = self.ctx.registry.types_items[@intCast(usize, it)];
                var sik_m: []const u8 = "SIK:n"; pal.markerWrite(sik_m);
                var sik_nb: [10]u8 = undefined; var sik_nl = itoa_mod.itoa(node_idx, sik_nb[0..]); var sik_ns: usize = @intCast(usize, 9) - @intCast(usize, sik_nl); pal.markerWrite(sik_nb[sik_ns..@intCast(usize, 9)]);
                var sik_km: []const u8 = "k"; pal.markerWrite(sik_km);
                var sik_kb: [10]u8 = undefined; var sik_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ts.kind)), sik_kb[0..]); var sik_ks: usize = @intCast(usize, 9) - @intCast(usize, sik_kl); pal.markerWrite(sik_kb[sik_ks..@intCast(usize, 9)]);
                var sik_nl2: []const u8 = "\n"; pal.markerWrite(sik_nl2);
                var r22_m: []const u8 = "R22:z"; pal.markerWrite(r22_m);
                var r22_zb: [10]u8 = undefined; var r22_zl = itoa_mod.itoa(ts.size, r22_zb[0..]); var r22_zs: usize = @intCast(usize, 9) - @intCast(usize, r22_zl); pal.markerWrite(r22_zb[r22_zs..@intCast(usize, 9)]);
                var r22_am: []const u8 = "a"; pal.markerWrite(r22_am);
                var r22_ab: [10]u8 = undefined; var r22_al = itoa_mod.itoa(ts.alignment, r22_ab[0..]); var r22_as: usize = @intCast(usize, 9) - @intCast(usize, r22_al); pal.markerWrite(r22_ab[r22_as..@intCast(usize, 9)]);
                var r22_nm: []const u8 = "n"; pal.markerWrite(r22_nm);
                var r22_nb: [10]u8 = undefined; var r22_nl = itoa_mod.itoa(ts.name_id, r22_nb[0..]); var r22_ns: usize = @intCast(usize, 9) - @intCast(usize, r22_nl); pal.markerWrite(r22_nb[r22_ns..@intCast(usize, 9)]);
                var r22_pm: []const u8 = "p"; pal.markerWrite(r22_pm);
                var r22_pb: [10]u8 = undefined; var r22_pl = itoa_mod.itoa(ts.payload_idx, r22_pb[0..]); var r22_ps: usize = @intCast(usize, 9) - @intCast(usize, r22_pl); pal.markerWrite(r22_pb[r22_ps..@intCast(usize, 9)]);
                var r22_nl3: []const u8 = "\n"; pal.markerWrite(r22_nl3);
                if (@enumToInt(ts.kind) == @enumToInt(type_mod.TypeKind.tagged_union_type)) {
                    var tp = self.ctx.registry.tu_items[@intCast(usize, ts.payload_idx)];
                    var fs: usize = @intCast(usize, tp.fields_start);
                    var fc: usize = @intCast(usize, tp.fields_count);
                    var fj: usize = @intCast(usize, 0);
                    while (fj < fc) : (fj += @intCast(usize, 1)) {
                        if (self.ctx.registry.fe_items[fs + fj].name_id == fi_name_id) {
                            var tag_val = nextTemp(self, type_mod.TYPE_U32);
                            emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, fj), .result = tag_val } });
                             emitInst(self, LirInst{ .assign_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = type_mod.TU_FIELD_TAG, .src = tag_val } });
                            var sin_m: []const u8 = "SIN:n"; pal.markerWrite(sin_m);
                            var sin_nb: [10]u8 = undefined; var sin_nl = itoa_mod.itoa(node_idx, sin_nb[0..]); var sin_ns: usize = @intCast(usize, 9) - @intCast(usize, sin_nl); pal.markerWrite(sin_nb[sin_ns..@intCast(usize, 9)]);
                            var sin_bm: []const u8 = "b"; pal.markerWrite(sin_bm);
                            var sin_bb: [10]u8 = undefined; var sin_bl = itoa_mod.itoa(base_temp, sin_bb[0..]); var sin_bs: usize = @intCast(usize, 9) - @intCast(usize, sin_bl); pal.markerWrite(sin_bb[sin_bs..@intCast(usize, 9)]);
                            var sin_fm: []const u8 = "f"; pal.markerWrite(sin_fm);
                            var sin_fb: [10]u8 = undefined; var sin_fl = itoa_mod.itoa(@intCast(u32, fj), sin_fb[0..]); var sin_fs: usize = @intCast(usize, 9) - @intCast(usize, sin_fl); pal.markerWrite(sin_fb[sin_fs..@intCast(usize, 9)]);
                            var sin_sm: []const u8 = "s"; pal.markerWrite(sin_sm);
                            var sin_sb: [10]u8 = undefined; var sin_sl = itoa_mod.itoa(val_temp, sin_sb[0..]); var sin_ss: usize = @intCast(usize, 9) - @intCast(usize, sin_sl); pal.markerWrite(sin_sb[sin_ss..@intCast(usize, 9)]);
                            var sin_nl2: []const u8 = "\n"; pal.markerWrite(sin_nl2);
                            if (self.ctx.registry.fe_items[fs + fj].type_id != type_mod.TYPE_VOID) {
                                if (!is_undef_arr_field) {

                                    emitInst(self, LirInst{ .assign_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = type_mod.TU_FIELD_PAYLOAD, .src = val_temp } });
                                }
                            }
                            break;
                        }
                    }
                } else if (@enumToInt(ts.kind) == @enumToInt(type_mod.TypeKind.struct_type)) {
                    var sp = self.ctx.registry.st_items[@intCast(usize, ts.payload_idx)];
                    var fs: usize = @intCast(usize, sp.fields_start);
                    var fc: usize = @intCast(usize, sp.fields_count);
                    var fj: usize = @intCast(usize, 0);
                    while (fj < fc) : (fj += @intCast(usize, 1)) {
                        if (self.ctx.registry.fe_items[fs + fj].name_id == fi_name_id) {
                            if (!is_undef_arr_field) {
                                var pk_fields: []type_mod.PackedBitField = undefined;
                                var packed_done: u8 = @intCast(u8, 0);
                                if (type_mod.typeRegistryIsPacked(self.ctx.registry, it)) {
                                    if (type_mod.typeRegistryGetPackedBitFields(self.ctx.registry, it, &pk_fields)) {
                                        if (fj < pk_fields.len) {
                                            var pkf = pk_fields[fj];
                                            emitInst(self, LirInst{ .store_bitfield = .{ .base = base_temp, .value = val_temp, .bit_offset = pkf.bit_offset, .bit_width = @intCast(u32, pkf.bit_width) } });
                                            packed_done = @intCast(u8, 1);
                                        }
                                    }
                                }
                                if (packed_done == @intCast(u8, 0)) {
                                    emitInst(self, LirInst{ .assign_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = @intCast(u32, fj), .src = val_temp } });
                                }
                            }
                            break;
                        }
                    }
                } else if (@enumToInt(ts.kind) == @enumToInt(type_mod.TypeKind.union_type) or @enumToInt(ts.kind) == @enumToInt(type_mod.TypeKind.packed_union_type)) {
                    var up = self.ctx.registry.un_items[@intCast(usize, ts.payload_idx)];
                    var fs: usize = @intCast(usize, up.fields_start);
                    var fc: usize = @intCast(usize, up.fields_count);
                    var fj: usize = @intCast(usize, 0);
                    while (fj < fc) : (fj += @intCast(usize, 1)) {
                        if (self.ctx.registry.fe_items[fs + fj].name_id == fi_name_id) {
                            if (!is_undef_arr_field and self.ctx.registry.fe_items[fs + fj].type_id != type_mod.TYPE_VOID) {
                                if (ts.kind == type_mod.TypeKind.packed_union_type) {
                                    var pk_fields: []type_mod.PackedBitField = undefined;
                                    if (type_mod.typeRegistryGetPackedUnionBitFields(self.ctx.registry, it, &pk_fields)) {
                                        if (fj < pk_fields.len) {
                                            if (self.ctx.registry.fe_items[fs + fj].type_id < @intCast(u32, self.ctx.registry.types_len)) {
                                                var mty = self.ctx.registry.types_items[@intCast(usize, self.ctx.registry.fe_items[fs + fj].type_id)];
                                                if (mty.kind == type_mod.TypeKind.struct_type and (mty.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                                                    var wsv_msg: []const u8 = "cannot assign a whole packed-struct value to a packed union member (bit-slice store not supported)";
                                                    _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, 3000), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), wsv_msg);
                                                    return base_temp;
                                                }
                                            }
                                            var pkf = pk_fields[fj];
                                            emitInst(self, LirInst{ .store_bitfield = .{ .base = base_temp, .value = val_temp, .bit_offset = pkf.bit_offset, .bit_width = @intCast(u32, pkf.bit_width) } });
                                            break;
                                        }
                                    }
                                }
                                emitInst(self, LirInst{ .assign_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = @intCast(u32, fj), .src = val_temp } });
                            }
                            break;
                        }
                    }
                }
            }
        }
        return base_temp;
    } else if (node.kind == AstKind.tuple_literal) {
        var ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
        var tupm: []const u8 = "TUP\n"; pal.markerWrite(tupm);
        if (ec.len == 0) {
            return nextTemp(self, type_mod.TYPE_VOID);
        }
        var trt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        var trt_id: u32 = if (trt) |it| it else @intCast(u32, 0);
        if (trt_id != @intCast(u32, 0)) {
            var trt_ty = self.ctx.registry.types_items[@intCast(usize, trt_id)];
            if (trt_ty.kind == type_mod.TypeKind.array_type) {
                var ap = self.ctx.registry.array_items[@intCast(usize, trt_ty.payload_idx)];
                var base_temp = nextTemp(self, trt_id);
                var ei: usize = @intCast(usize, 0);
                while (ei < ec.len) : (ei += @intCast(usize, 1)) {
                    var val_temp = lowerExpr(self, ec[ei]);
                    var ix_temp = nextTemp(self, type_mod.TYPE_U32);
                    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, ei), .result = ix_temp } });
                    emitInst(self, LirInst{ .assign_index = .{ .name_id = @intCast(u32, 0), .base = base_temp, .index = ix_temp, .src = val_temp } });
                }
                return base_temp;
            }
        }
        return lowerExpr(self, ec[0]);
    } else if (node.kind == AstKind.swt_ex) {
        var swe_m: []const u8 = "SWE:s\n"; pal.markerWrite(swe_m);
        var cond_temp = lowerExpr(self, node.child_0);
        var cond_ty_id = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        var swc_m: []const u8 = "SWC:c"; pal.markerWrite(swc_m);
        var swc_cb: [10]u8 = undefined; var swc_cl = itoa_mod.itoa(node.child_0, swc_cb[0..]); var swc_cs: usize = @intCast(usize, 9) - @intCast(usize, swc_cl); pal.markerWrite(swc_cb[swc_cs..@intCast(usize, 9)]);
        if (cond_ty_id) |swv| {
            var swc_rm: []const u8 = "R"; pal.markerWrite(swc_rm);
            var swc_rb: [10]u8 = undefined; var swc_rl2 = itoa_mod.itoa(swv, swc_rb[0..]); var swc_rs: usize = @intCast(usize, 9) - @intCast(usize, swc_rl2); pal.markerWrite(swc_rb[swc_rs..@intCast(usize, 9)]);
        } else {
            var swc_x: []const u8 = "X"; pal.markerWrite(swc_x);
        }
        var swc_nl2: []const u8 = "\n"; pal.markerWrite(swc_nl2);
        var tu_base_box: [1]u32 = [1]u32{cond_temp};
        var tu_type_box: [1]u32 = [1]u32{@intCast(u32, 0)};
        if (cond_ty_id) |ct| {
            tu_type_box[0] = ct;
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                 emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = cond_temp, .field_id = type_mod.TU_FIELD_TAG, .result = tag_temp } });
                cond_temp = tag_temp;
            }
        }
        var sw_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        {
            var swrt_m: []const u8 = "SWRT:n"; pal.markerWrite(swrt_m);
            var swrt_b: [10]u8 = undefined; var swrt_l = itoa_mod.itoa(node_idx, swrt_b[0..]); var swrt_s: usize = @intCast(usize, 9) - @intCast(usize, swrt_l); pal.markerWrite(swrt_b[swrt_s..@intCast(usize, 9)]);
            var swrt_x: []const u8 = "t"; pal.markerWrite(swrt_x);
            if (sw_rt) |srt| {
                var swrt_rb: [10]u8 = undefined; var swrt_rl = itoa_mod.itoa(srt, swrt_rb[0..]); var swrt_rs: usize = @intCast(usize, 9) - @intCast(usize, swrt_rl); pal.markerWrite(swrt_rb[swrt_rs..@intCast(usize, 9)]);
            } else {
                var swrt_z: []const u8 = "M"; pal.markerWrite(swrt_z);
            }
            var swrt_nl: []const u8 = "\n"; pal.markerWrite(swrt_nl);
        }
        var result_tid: u32 = if (sw_rt) |t| (if (t != type_mod.TYPE_UNDEFINED and t != type_mod.TYPE_VOID) t else type_mod.TYPE_VOID) else type_mod.TYPE_VOID;
        var result_temp = nextTemp(self, result_tid);
        var prong_ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
        var switch_bb = self.current_bb;
        var prong_start = @intCast(u32, self.func.blocks.len);
        var pi: usize = 0;
        while (pi < prong_ec.len) : (pi += 1) { _ = createBlock(self); }
        var else_bb = createBlock(self);
        var exit_bb = createBlock(self);
        var cases_start = @intCast(u32, self.func.switch_cases.len);
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = ast_mod.astStoreNodeAt(store, prong_ec[pi]);
            if ((prong_node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) { continue; }
            var prong_bb_id = prong_start + @intCast(u32, pi);
            var case_ec = ast_mod.astStoreNodeExtraChildren(store, prong_ec[pi]);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                lowerAppendSwitchCaseItem(self, case_ec[ci], prong_bb_id, cond_ty_id);
            }
        }
        var sc_len = @intCast(u32, self.func.switch_cases.len);
        var cases_count: u32 = sc_len - cases_start;
        var else_target = else_bb;
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = ast_mod.astStoreNodeAt(store, prong_ec[pi]);
            if ((prong_node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) {
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
            var prong_node = ast_mod.astStoreNodeAt(store, prong_ec[pi]);
            var lf16_m: []const u8 = "LF16:n"; pal.markerWrite(lf16_m);
            var lf16_fb: [10]u8 = undefined; var lf16_fl = itoa_mod.itoa(@intCast(u32, prong_node.flags), lf16_fb[0..]); var lf16_fs: usize = @intCast(usize, 9) - @intCast(usize, lf16_fl); pal.markerWrite(lf16_fb[lf16_fs..@intCast(usize, 9)]);
            var lf16_cm: []const u8 = "c1="; pal.markerWrite(lf16_cm);
            var lf16_cb: [10]u8 = undefined; var lf16_cl = itoa_mod.itoa(prong_node.child_1, lf16_cb[0..]); var lf16_cs: usize = @intCast(usize, 9) - @intCast(usize, lf16_cl); pal.markerWrite(lf16_cb[lf16_cs..@intCast(usize, 9)]);
            var lf16_sp: []const u8 = "t"; pal.markerWrite(lf16_sp);
            var lf16_tb: [10]u8 = undefined; var lf16_tl = itoa_mod.itoa(tu_type_box[0], lf16_tb[0..]); var lf16_ts: usize = @intCast(usize, 9) - @intCast(usize, lf16_tl); pal.markerWrite(lf16_tb[lf16_ts..@intCast(usize, 9)]);
            var lf16_n: []const u8 = "\n"; pal.markerWrite(lf16_n);
        var prong_bb_id: u32 = prong_start + @intCast(u32, pi);
            self.current_bb = prong_bb_id;
            self.block_terminated = @intCast(u8, 0);
            if ((prong_node.flags & @intCast(u8, 16)) != @intCast(u8, 0)) {
                var capture_name = prong_node.child_1;
                if (tu_type_box[0] != @intCast(u32, 0)) {
                    var cap1_m: []const u8 = "CAP1\n"; pal.markerWrite(cap1_m);
                    var tu_ty = self.ctx.registry.types_items[@intCast(usize, tu_type_box[0])];
                    var tp = self.ctx.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
                    var case_ec = ast_mod.astStoreNodeExtraChildren(store, prong_ec[pi]);
                    var capy_m: []const u8 = "CAPY:n"; pal.markerWrite(capy_m);
                    var capy_pb: [10]u8 = undefined; var capy_pl = itoa_mod.itoa(@intCast(u32, ast_mod.astStoreNodePayloadPacked(store, prong_ec[pi], prong_node.kind) & @intCast(u64, 0xFFFFFFFF)), capy_pb[0..]); var capy_ps: usize = @intCast(usize, 9) - @intCast(usize, capy_pl); pal.markerWrite(capy_pb[capy_ps..@intCast(usize, 9)]);
                    var capy_lm: []const u8 = "l"; pal.markerWrite(capy_lm);
                    var capy_lb: [10]u8 = undefined; var capy_ll = itoa_mod.itoa(@intCast(u32, case_ec.len), capy_lb[0..]); var capy_ls: usize = @intCast(usize, 9) - @intCast(usize, capy_ll); pal.markerWrite(capy_lb[capy_ls..@intCast(usize, 9)]);
                    var capy_n: []const u8 = "\n"; pal.markerWrite(capy_n);
                    if (case_ec.len > @intCast(usize, 0)) {
                        var ev3 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, case_ec[0]);
                        if (ev3) |idx| {
                        var fe: type_mod.FieldEntry = self.ctx.registry.fe_items[@intCast(usize, tp.fields_start) + @intCast(usize, idx)];
                        capture_name = maybeDisambiguateCapture(self, capture_name, fe.type_id);
                        var payload_temp = nextTemp(self, fe.type_id);
                        _ = hash_mod.u32ToU32MapPut(&self.func.temp_variant_sub_field, payload_temp, @intCast(u32, 0));
                         emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = tu_base_box[0], .field_id = type_mod.TU_FIELD_PAYLOAD, .result = payload_temp } });
                        addLocalDecl(self, capture_name, fe.type_id, payload_temp, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1));
                        emitInst(self, LirInst{ .decl_local = .{ .name_id = capture_name, .type_id = fe.type_id, .temp = payload_temp } });
                    }
                     } else {
                         addLocalDecl(self, capture_name, tu_type_box[0], tu_base_box[0], self.scope_depth + @intCast(u32, 1), @intCast(u8, 1));
                         emitInst(self, LirInst{ .decl_local = .{ .name_id = capture_name, .type_id = tu_type_box[0], .temp = tu_base_box[0] } });
                     }
                }
            }
            var body_node = ast_mod.astStoreNodeAt(store, prong_node.child_0);
            var prong_val: u32 = @intCast(u32, 0);
            if (body_node.kind == AstKind.block) {
                pushScopeDepth(self);
                var block_ec = ast_mod.astStoreNodeExtraChildren(store, prong_node.child_0);
                var bj: usize = 0;
                while (bj < block_ec.len) : (bj += 1) {
                    lowerStmt(self, block_ec[bj]);
                }
                popScopeDepth(self);
                prong_val = @intCast(u32, 0);
            } else {
                prong_val = lowerExpr(self, prong_node.child_0);
                var sw_int: SrcIntent = SrcIntent.value;
                if (body_node.kind == AstKind.null_literal) { sw_int = SrcIntent.null_src; }
                if (body_node.kind == AstKind.error_literal) { sw_int = SrcIntent.error_src; }
                prong_val = materializeInto(self, prong_val, result_tid, sw_int);
            }
            self.pending_scope = TEMP_NONE;

            var swp_m: []const u8 = "SWP:p"; pal.markerWrite(swp_m);
            var swp_pb: [10]u8 = undefined; var swp_pl = itoa_mod.itoa(prong_val, swp_pb[0..]); var swp_ps: usize = @intCast(usize, 9) - @intCast(usize, swp_pl); pal.markerWrite(swp_pb[swp_ps..@intCast(usize, 9)]);
            var swp_rb: [10]u8 = undefined; var swp_rl = itoa_mod.itoa(result_temp, swp_rb[0..]); var swp_rs: usize = @intCast(usize, 9) - @intCast(usize, swp_rl); pal.markerWrite(swp_rb[swp_rs..@intCast(usize, 9)]);
            var swp_nl: []const u8 = "\n"; pal.markerWrite(swp_nl);
            if (self.block_terminated == @intCast(u8, 0)) {
                var swa_m: []const u8 = "SWA:d"; pal.markerWrite(swa_m);
                var swa_db: [10]u8 = undefined; var swa_dl = itoa_mod.itoa(result_temp, swa_db[0..]); var swa_ds: usize = @intCast(usize, 9) - @intCast(usize, swa_dl); pal.markerWrite(swa_db[swa_ds..@intCast(usize, 9)]);
                var swa_sb: [10]u8 = undefined; var swa_sl = itoa_mod.itoa(prong_val, swa_sb[0..]); var swa_ss: usize = @intCast(usize, 9) - @intCast(usize, swa_sl); pal.markerWrite(swa_sb[swa_ss..@intCast(usize, 9)]);
                var swa_nl: []const u8 = "\n"; pal.markerWrite(swa_nl);
                emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = result_temp, .src = prong_val } });
                emitInst(self, LirInst{ .jump = exit_bb });
            }

            self.capture_shadow.count = @intCast(usize, 0);
        }
        var swx_m: []const u8 = "SWEXIT:bt"; pal.markerWriteInt(swx_m, @intCast(u32, self.block_terminated));
        self.block_terminated = @intCast(u8, 0);
        self.current_bb = exit_bb;
        return result_temp;
     } else if (node.kind == AstKind.slice_expr) {
         var se_base = lowerExpr(self, node.child_0);
         var se_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
         var sem_m: []const u8 = "SEM:bt"; pal.markerWrite(sem_m);
         var sem_tb: [10]u8 = undefined; var sem_tl = itoa_mod.itoa(se_base, sem_tb[0..]); var sem_ts: usize = @intCast(usize, 9) - @intCast(usize, sem_tl); pal.markerWrite(sem_tb[sem_ts..@intCast(usize, 9)]);
         var sem_bm: []const u8 = "h"; pal.markerWrite(sem_bm);
         var sem_bb: [10]u8 = undefined; var sem_bl = itoa_mod.itoa(self.hoisted_temps.items[@intCast(usize, se_base)].type_id, sem_bb[0..]); var sem_bs: usize = @intCast(usize, 9) - @intCast(usize, sem_bl); pal.markerWrite(sem_bb[sem_bs..@intCast(usize, 9)]);
         var sem_nl: []const u8 = "\n"; pal.markerWrite(sem_nl);
         var se_bt_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
          if (se_rt) |st| {
             var ser_nl: []const u8 = "SER:F\n"; pal.markerWrite(ser_nl);
             var se_bt = self.hoisted_temps.items[@intCast(usize, se_base)].type_id;
             se_bt_box[0] = se_bt;

            var sec2_m: []const u8 = "SEC2:"; pal.markerWrite(sec2_m); var sec2_b: [10]u8 = undefined; var sec2_l = itoa_mod.itoa(node.child_2, sec2_b[0..]); var sec2_s: usize = @intCast(usize, 9) - @intCast(usize, sec2_l); pal.markerWrite(sec2_b[sec2_s..@intCast(usize, 9)]); var sec2_nl: []const u8 = "\n"; pal.markerWrite(sec2_nl);
            var se_slice_ptr: u32 = se_base;
            var se_slice_len_box: [1]u32 = [1]u32{TEMP_NONE};
            if (se_bt != type_mod.TYPE_UNDEFINED) {
                var se_bty = self.ctx.registry.types_items[@intCast(usize, se_bt)];
                if (se_bty.kind == type_mod.TypeKind.slice_type) {
                    var se_sl = self.ctx.registry.slice_items[@intCast(usize, se_bty.payload_idx)];
                    var se_pty = type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, se_sl.elem, false);
                    se_slice_ptr = nextTemp(self, se_pty);
                    var se_slnid = nameMapGet(self, se_base);
                    emitInst(self, LirInst{ .load_field = .{ .name_id = se_slnid, .base = se_base, .field_id = type_mod.SLICE_FIELD_PTR, .result = se_slice_ptr } });
                    se_slice_len_box[0] = nextTemp(self, type_mod.TYPE_USIZE);
                     emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = se_base, .field_id = type_mod.SLICE_FIELD_LEN, .result = se_slice_len_box[0] } });
                } else if (se_bty.kind == type_mod.TypeKind.array_type) {
                    var se_arr = self.ctx.registry.array_items[@intCast(usize, se_bty.payload_idx)];
                    var se_mpty = type_mod.typeRegistryGetOrCreateManyPtr(self.ctx.registry, se_arr.elem, false);
                    se_slice_ptr = nextTemp(self, se_mpty);
                    emitInst(self, LirInst{ .ptr_cast = .{ .value = se_base, .target = se_mpty, .result = se_slice_ptr } });
                    se_slice_len_box[0] = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, se_arr.length), .result = se_slice_len_box[0] } });
                }
            }
            if (node.child_2 != @intCast(u32, 0)) {
                var se_end = lowerExpr(self, node.child_2);
                var se_ptr = se_slice_ptr;
                var se_len = se_end;
                if (node.child_1 != @intCast(u32, 0)) {
                    var se_start = lowerExpr(self, node.child_1);
                    var se_ppty2 = self.hoisted_temps.items[@intCast(usize, se_slice_ptr)].type_id;
                    se_ptr = nextTemp(self, se_ppty2);
                    emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = se_slice_ptr, .rhs = se_start, .result = se_ptr } });
                    se_len = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = se_end, .rhs = se_start, .result = se_len } });
                }
                var se_result = nextTemp(self, st);
                emitInst(self, LirInst{ .make_slice = .{ .ptr = se_ptr, .len = se_len, .result = se_result, .type_id = st } });
                return se_result;
            }
            var r1a_m: []const u8 = "R1A\n"; pal.markerWrite(r1a_m);
            if (node.child_1 != @intCast(u32, 0)) {
                var se_start = lowerExpr(self, node.child_1);
                var se_ppty = self.hoisted_temps.items[@intCast(usize, se_slice_ptr)].type_id;
                var se_new_ptr = nextTemp(self, se_ppty);
                emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = se_slice_ptr, .rhs = se_start, .result = se_new_ptr } });
                if (se_slice_len_box[0] != TEMP_NONE) {
                    var se_new_len = nextTemp(self, type_mod.TYPE_USIZE);
                    emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = se_slice_len_box[0], .rhs = se_start, .result = se_new_len } });
                    var se_result = nextTemp(self, st);
                    emitInst(self, LirInst{ .make_slice = .{ .ptr = se_new_ptr, .len = se_new_len, .result = se_result, .type_id = st } });
                    var r1a_mks: []const u8 = "MKS:r"; pal.markerWrite(r1a_mks); var r1a_rb: [10]u8 = undefined; var r1a_rl = itoa_mod.itoa(se_result, r1a_rb[0..]); var r1a_rs: usize = @intCast(usize, 9) - @intCast(usize, r1a_rl); pal.markerWrite(r1a_rb[r1a_rs..@intCast(usize, 9)]); var r1a_nl: []const u8 = "\n"; pal.markerWrite(r1a_nl);
                    return se_result;
                }
            }
          } else {
             var ser_m: []const u8 = "SER:M\n"; pal.markerWrite(ser_m);
          }
          var ret0_m: []const u8 = "RET0\n"; pal.markerWrite(ret0_m);
          iceSliceUnsupported(self, node_idx);
          return @intCast(u32, 0);
     } else if (node.kind == AstKind.add_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_ADD, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.sub_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_SUB, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.mul_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_MUL, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.wrap_add_assign or node.kind == AstKind.wrap_sub_assign or node.kind == AstKind.wrap_mul_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        if (node.kind == AstKind.wrap_add_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else if (node.kind == AstKind.wrap_sub_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WSUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WMUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        }
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.sat_add_assign or node.kind == AstKind.sat_sub_assign or node.kind == AstKind.sat_mul_assign or node.kind == AstKind.sat_shl_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        if (node.kind == AstKind.sat_add_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else if (node.kind == AstKind.sat_sub_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SSUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else if (node.kind == AstKind.sat_mul_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SMUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SSHL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        }
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.div_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckDivMod(self, lhs_val, rhs_val);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_DIV, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.mod_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckDivMod(self, lhs_val, rhs_val);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MOD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.shl_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckShift(self, lhs_val, rhs_val);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_SHL, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.shr_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckShift(self, lhs_val, rhs_val);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.and_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.xor_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XOR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.or_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_OR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
        return op_r;
    } else if (node.kind == AstKind.block) {
        var blk_ec = ast_mod.astStoreNodeExtraChildren(self.ctx.store, node_idx);
        if (blk_ec.len > @intCast(usize, 0)) {
            var blk_last = blk_ec[blk_ec.len - 1];
            var blk_last_nd = ast_mod.astStoreNodeAt(self.ctx.store, blk_last);
            if (!lowerIsNoValueStmtKind(blk_last_nd.kind)) {
                pushScopeDepth(self);
                var blj: usize = 0;
                while (blj < blk_ec.len - 1) : (blj += 1) {
                    self.block_terminated = @intCast(u8, 0);
                    lowerStmt(self, blk_ec[blj]);
                }
                self.block_terminated = @intCast(u8, 0);
                var blk_val = lowerExpr(self, blk_last);
                expandDefers(self, self.scope_depth, @intCast(u8, 0), @intCast(u8, 1));
                popScopeDepth(self);
                return blk_val;
            }
        }
        var void_temp = nextTemp(self, type_mod.TYPE_VOID);
        lowerStmtBody(self, node_idx);
        return void_temp;
    } else if (node.kind == AstKind.labeled_stmt) {
        var ls_void = nextTemp(self, type_mod.TYPE_VOID);
        lowerStmt(self, node_idx);
        return ls_void;
    } else {
        return @intCast(u32, 0);
    }
}

fn lowerIsNoValueStmtKind(kind: AstKind) bool {
    if (kind == AstKind.return_stmt) return true;
    if (kind == AstKind.break_stmt) return true;
    if (kind == AstKind.continue_stmt) return true;
    if (kind == AstKind.block) return true;
    if (kind == AstKind.var_decl) return true;
    if (kind == AstKind.expr_stmt) return true;
    if (kind == AstKind.defer_stmt) return true;
    if (kind == AstKind.if_stmt) return true;
    if (kind == AstKind.while_stmt) return true;
    if (kind == AstKind.for_stmt) return true;
    return false;
}

fn lowerExprOrBlock(self: *LirLowerer, node_idx: u32) u32 {
    var body_node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    if (body_node.kind == AstKind.block) {
        var block_ec = ast_mod.astStoreNodeExtraChildren(self.ctx.store, node_idx);
        if (block_ec.len > @intCast(usize, 0)) {
            var blk_last = block_ec[block_ec.len - 1];
            var blk_last_nd = ast_mod.astStoreNodeAt(self.ctx.store, blk_last);
            if (!lowerIsNoValueStmtKind(blk_last_nd.kind)) {
                var bj: usize = 0;
                while (bj < block_ec.len - 1) : (bj += 1) {
                    lowerStmt(self, block_ec[bj]);
                }
                return lowerExpr(self, blk_last);
            }
        }
        var bj: usize = 0;
        while (bj < block_ec.len) : (bj += 1) {
            lowerStmt(self, block_ec[bj]);
        }
        return @intCast(u32, 0);
    }
    if (body_node.kind == AstKind.return_stmt or body_node.kind == AstKind.break_stmt or body_node.kind == AstKind.continue_stmt) {
        lowerStmt(self, node_idx);
        return @intCast(u32, 0);
    }
    return lowerExpr(self, node_idx);
}

fn lowerStmtBody(self: *LirLowerer, node_idx: u32) void {
    pushScopeDepth(self);
    var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    if (node.kind == AstKind.block) {
        var ec = ast_mod.astStoreNodeExtraChildren(self.ctx.store, node_idx);
        var i: usize = 0;
        while (i < ec.len) : (i += 1) {
            var blc_node = ast_mod.astStoreNodeAt(self.ctx.store, ec[i]);
            var blc_m: []const u8 = "BLC:n"; pal.markerWrite(blc_m);
            var blc_nb: [10]u8 = undefined; var blc_nl = itoa_mod.itoa(ec[i], blc_nb[0..]); var blc_ns: usize = @intCast(usize, 9) - @intCast(usize, blc_nl); pal.markerWrite(blc_nb[blc_ns..@intCast(usize, 9)]);
            var blc_km: []const u8 = "k"; pal.markerWrite(blc_km);
            var blc_kb: [10]u8 = undefined; var blc_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(blc_node.kind)), blc_kb[0..]); var blc_ks: usize = @intCast(usize, 9) - @intCast(usize, blc_kl); pal.markerWrite(blc_kb[blc_ks..@intCast(usize, 9)]);
            var blc_nl2: []const u8 = "\n"; pal.markerWrite(blc_nl2);
            self.block_terminated = @intCast(u8, 0);
            lowerStmt(self, ec[i]);
        }
    } else {
        lowerStmt(self, node_idx);
    }
    expandDefers(self, self.scope_depth, @intCast(u8, 0), @intCast(u8, 1));
    popScopeDepth(self);
}

pub fn lowerStmt(self: *LirLowerer, node_idx: u32) void {
    self._ctx_node_idx = node_idx;
    self._ctx_node_kind = @intCast(u32, @enumToInt(ast_mod.astStoreNodeAt(self.ctx.store, node_idx).kind));
    var stkm: []const u8 = "STK:n"; pal.markerWrite(stkm);
    var stknb: [10]u8 = undefined; var stknl = itoa_mod.itoa(node_idx, stknb[0..]); var stkns: usize = @intCast(usize, 9) - @intCast(usize, stknl); pal.markerWrite(stknb[stkns..@intCast(usize, 9)]);
    var stkkm: []const u8 = "k"; pal.markerWrite(stkkm);
    var stkkb: [10]u8 = undefined; var stkkl = itoa_mod.itoa(self._ctx_node_kind, stkkb[0..]); var stkks: usize = @intCast(usize, 9) - @intCast(usize, stkkl); pal.markerWrite(stkkb[stkks..@intCast(usize, 9)]);
    var stknl2: []const u8 = "\n"; pal.markerWrite(stknl2);
    var node = ast_mod.astStoreNodeAt(self.ctx.store, node_idx);
    var store = self.ctx.store;
    if (node.kind == AstKind.block) {
        pushScopeDepth(self);
        var ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
        var i: usize = 0;
        while (i < ec.len) : (i += 1) {
            lowerStmt(self, ec[i]);
        }
        expandDefers(self, self.scope_depth, @intCast(u8, 0), @intCast(u8, 1));
        popScopeDepth(self);
    } else if (node.kind == AstKind.labeled_stmt) {
        var saved_label = self.current_label;
        self.current_label = ast_mod.astStoreNodePayload(store, node_idx);
        if (node.child_0 != @intCast(u32, 0)) {
            var ls_child = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
            if (ls_child.kind == AstKind.block) {
                var ls_exit_bb = createBlock(self);
                var ls_loop_info = LoopInfo{ .header_bb = ls_exit_bb, .exit_bb = ls_exit_bb, .scope_depth = self.scope_depth, .label_id = self.current_label, .is_loop = @intCast(u8, 0) };
                loopInfoArrayListAppend(&self.loop_stack, ls_loop_info);
                lowerStmt(self, node.child_0);
                if (self.block_terminated == @intCast(u8, 0)) {
                    emitInst(self, LirInst{ .jump = ls_exit_bb });
                }
                self.current_bb = ls_exit_bb;
                self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
            } else {
                lowerStmt(self, node.child_0);
            }
        }
        self.current_label = saved_label;
    } else if (node.kind == AstKind.defer_stmt) {
        pushDefer(self, @intCast(u8, 0), node.child_0);
    } else if (node.kind == AstKind.errdefer_stmt) {
        pushDefer(self, @intCast(u8, 1), node.child_0);
    } else if (node.kind == AstKind.if_stmt) {
        var if_fold = hash_mod.u32ToU64MapGet(self.ctx.comptime_values, node.child_0);
        if (if_fold) |ifv| {
            if (ast_mod.astStoreNodePayload(store, node_idx) == @intCast(u32, 0)) {
                if (ifv != @intCast(u64, 0)) {
                    self.block_terminated = @intCast(u8, 0);
                    lowerStmtBody(self, node.child_1);
                } else {
                    self.block_terminated = @intCast(u8, 0);
                    if (node.child_2 != @intCast(u32, 0)) {
                        lowerStmtBody(self, node.child_2);
                    }
                }
                self.block_terminated = @intCast(u8, 0);
                return;
            }
        }
        var if_c0: []const u8 = "IF:c0="; pal.markerWrite(if_c0);
        var if_c0b: [10]u8 = undefined; var if_c0l = itoa_mod.itoa(node.child_0, if_c0b[0..]); var if_c0s: usize = @intCast(usize, 9) - @intCast(usize, if_c0l); pal.markerWrite(if_c0b[if_c0s..@intCast(usize, 9)]);
        var if_kh: []const u8 = " k="; pal.markerWrite(if_kh);
        if (node.child_0 != @intCast(u32, 0)) {
            var cond_n = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
            var if_ckl = itoa_mod.itoa(cond_n.kind, if_c0b[0..]); var if_cks: usize = @intCast(usize, 9) - @intCast(usize, if_ckl); pal.markerWrite(if_c0b[if_cks..@intCast(usize, 9)]);
        } else {
            var if_z: []const u8 = "ZERO"; pal.markerWrite(if_z);
        }
        var if_nl: []const u8 = "\n"; pal.markerWrite(if_nl);
        var cond_temp = TEMP_NONE;
        var orig_cond_temp = TEMP_NONE;
        var cond_node = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        if (cond_node.kind == AstKind.field_access) {
            var fa_base_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, cond_node.child_0);
            if (fa_base_rt) |fbrt| {
                var fbrt_ty = self.ctx.registry.types_items[@intCast(usize, fbrt)];
                if (fbrt_ty.kind == type_mod.TypeKind.tagged_union_type) {
                    var tu_tp = self.ctx.registry.tu_items[@intCast(usize, fbrt_ty.payload_idx)];
                    var tstart: usize = @intCast(usize, tu_tp.fields_start);
                    var tcount: usize = @intCast(usize, tu_tp.fields_count);
                    var tfi: usize = 0;
                    while (tfi < tcount) : (tfi += 1) {
                        if (self.ctx.registry.fe_items[tstart + tfi].name_id == ast_mod.astStoreNodePayload(store, node.child_0)) { break; }
                    }
                    if (tfi < tcount) {
                        var tu_base = lowerExpr(self, cond_node.child_0);
                        var tg_nid = nameMapGet(self, tu_base);
                        var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                        emitInst(self, LirInst{ .load_field = .{ .name_id = tg_nid, .base = tu_base, .field_id = type_mod.TU_FIELD_TAG, .result = tag_temp } });
                        var vidx_temp = nextTemp(self, type_mod.TYPE_U32);
                        emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, tfi), .result = vidx_temp } });
                        var tcond = nextTemp(self, type_mod.TYPE_BOOL);
                        emitInst(self, LirInst{ .binary = .{ .op = BIN_EQ, .lhs = tag_temp, .rhs = vidx_temp, .result = tcond } });
                        cond_temp = tcond;
                        orig_cond_temp = tu_base;
                    }
                }
            }
        }
        if (cond_temp == TEMP_NONE) {
            cond_temp = lowerExpr(self, node.child_0);
            orig_cond_temp = cond_temp;
        }
        var cond_ty_id = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
        if (cond_ty_id) |ct| {
            var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
            if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var a3b: []const u8 = "F3bT"; pal.markerWrite(a3b);
                var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                var tgn2 = nameMapGet(self, cond_temp);
                emitInst(self, LirInst{ .load_field = .{ .name_id = tgn2, .base = cond_temp, .field_id = type_mod.TU_FIELD_TAG, .result = tag_temp } });
                cond_temp = tag_temp;
            }
        }
        if (@intCast(usize, cond_temp) < self.hoisted_temps.len) {
            var cond_t = getTempType(self, cond_temp);
            if (cond_t != type_mod.TYPE_UNDEFINED) {
                var cond_ty = self.ctx.registry.types_items[@intCast(usize, cond_t)];
                if (cond_ty.kind == type_mod.TypeKind.optional_type) {
                    var gapc_ci3: []const u8 = "GAPC:ci3\n"; pal.markerWrite(gapc_ci3);
                    var has_val = nextTemp(self, type_mod.TYPE_U8);
                    emitInst(self, LirInst{ .check_optional = .{ .value = cond_temp, .result = has_val } });
                    var gapc_ci4: []const u8 = "GAPC:ci4\n"; pal.markerWrite(gapc_ci4);
                    cond_temp = has_val;
                }
            }
        }
        if (@intCast(usize, cond_temp) < self.hoisted_temps.len) {
        var d10m: []const u8 = "D10:k"; pal.markerWrite(d10m);
        var cond_node_k = ast_mod.astStoreNodeAt(self.ctx.store, node.child_0);
        var d10kb: [20]u8 = undefined; var d10kl = itoa_mod.itoa(cond_node_k.kind, d10kb[0..]); var d10ks: usize = @intCast(usize, 19) - @intCast(usize, d10kl); pal.markerWrite(d10kb[d10ks..@intCast(usize, 19)]);
        var d10mc: []const u8 = "c"; pal.markerWrite(d10mc);
        var d10cb: [20]u8 = undefined; var d10cl = itoa_mod.itoa(cond_temp, d10cb[0..]); var d10cs: usize = @intCast(usize, 19) - @intCast(usize, d10cl); pal.markerWrite(d10cb[d10cs..@intCast(usize, 19)]);
        var d10t: []const u8 = "t"; pal.markerWrite(d10t);
        var d10tb: [20]u8 = undefined; var d10tl = itoa_mod.itoa(self.hoisted_temps.items[@intCast(usize, cond_temp)].type_id, d10tb[0..]); var d10ts: usize = @intCast(usize, 19) - @intCast(usize, d10tl); pal.markerWrite(d10tb[d10ts..@intCast(usize, 19)]);
        var d10nl: []const u8 = "\n"; pal.markerWrite(d10nl);
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
        if (ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
            var icap_idx = ast_mod.astStoreNodePayload(store, node_idx);
            var icapn = ast_mod.astStoreNodeAt(self.ctx.store, icap_idx);
            if (icapn.kind == AstKind.if_capture) {
                bindOptionalCapture(self, icap_idx, orig_cond_temp);
            }
        }
        var ifb_m: []const u8 = "IFB:b"; pal.markerWrite(ifb_m);
        var ifb_bb: [10]u8 = undefined; var ifb_bl = itoa_mod.itoa(node.child_1, ifb_bb[0..]); var ifb_bs: usize = @intCast(usize, 9) - @intCast(usize, ifb_bl); pal.markerWrite(ifb_bb[ifb_bs..@intCast(usize, 9)]);
        var ifb_nl: []const u8 = "\n"; pal.markerWrite(ifb_nl);
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
            self.block_terminated = @intCast(u8, 0);
        } else {
            self.block_terminated = @intCast(u8, 0);
        }
        self.current_bb = join_bb;
        self.capture_shadow.count = @intCast(usize, 0);
    } else if (node.kind == AstKind.while_stmt) {
        var mw_m: []const u8 = "MW:en"; pal.markerWrite(mw_m);
        var mw_b: [20]u8 = undefined; var mw_l = itoa_mod.itoa(node.child_0, mw_b[0..]); var mw_s: usize = @intCast(usize, 19) - @intCast(usize, mw_l); pal.markerWrite(mw_b[mw_s..@intCast(usize, 19)]);
        var mw_nl: []const u8 = "\n"; pal.markerWrite(mw_nl);
        var mwc2: []const u8 = "ZW2:"; pal.markerWrite(mwc2);
        var mwc2b: [10]u8 = undefined; var mwc2l = itoa_mod.itoa(node.child_2, mwc2b[0..]); var mwc2s: usize = @intCast(usize, 9) - @intCast(usize, mwc2l); pal.markerWrite(mwc2b[mwc2s..@intCast(usize, 9)]);
        var mwc2n: []const u8 = "\n"; pal.markerWrite(mwc2n);
        var mwp: []const u8 = "MW:pl"; pal.markerWrite(mwp);
        var mwpb: [10]u8 = undefined; var mwpl = itoa_mod.itoa(ast_mod.astStoreNodePayload(store, node_idx), mwpb[0..]); var mwps: usize = @intCast(usize, 9) - @intCast(usize, mwpl); pal.markerWrite(mwpb[mwps..@intCast(usize, 9)]);
        var mwpn: []const u8 = "\n"; pal.markerWrite(mwpn);
        var entry_bb = self.current_bb;
        var cond_bb = createBlock(self);
        var body_bb = createBlock(self);
        var exit_bb = createBlock(self);
        var cont_bb = createBlock(self);
        var loop_info = LoopInfo{
            .header_bb = cont_bb,
            .exit_bb = exit_bb,
            .scope_depth = self.scope_depth,
            .label_id = self.current_label,
            .is_loop = @intCast(u8, 1),
        };
        loopInfoArrayListAppend(&self.loop_stack, loop_info);
        emitInst(self, LirInst{ .jump = cond_bb });
        markTerminated(&self.func.blocks, entry_bb);
        self.current_bb = cond_bb;
        var cond_temp = lowerExpr(self, node.child_0);
        var orig_cond_temp = cond_temp;
        var mwc_m: []const u8 = "MW:c"; pal.markerWrite(mwc_m);
        var mwc_b: [20]u8 = undefined; var mwc_l = itoa_mod.itoa(cond_temp, mwc_b[0..]); var mwc_s: usize = @intCast(usize, 19) - @intCast(usize, mwc_l); pal.markerWrite(mwc_b[mwc_s..@intCast(usize, 19)]);
        if (@intCast(usize, cond_temp) < self.hoisted_temps.len) {
            var mwc_t: []const u8 = "t"; pal.markerWrite(mwc_t);
            var mwc_tb: [20]u8 = undefined; var mwc_tl = itoa_mod.itoa(self.hoisted_temps.items[@intCast(usize, cond_temp)].type_id, mwc_tb[0..]); var mwc_ts: usize = @intCast(usize, 19) - @intCast(usize, mwc_tl); pal.markerWrite(mwc_tb[mwc_ts..@intCast(usize, 19)]);
        }
        var mwc_nl: []const u8 = "\n"; pal.markerWrite(mwc_nl);
        if (@intCast(usize, cond_temp) < self.hoisted_temps.len) {
            var cond_t = getTempType(self, cond_temp);
            if (cond_t != type_mod.TYPE_UNDEFINED) {
                var cond_ty = self.ctx.registry.types_items[@intCast(usize, cond_t)];
                if (cond_ty.kind == type_mod.TypeKind.optional_type) {
                    var has_val = nextTemp(self, type_mod.TYPE_U8);
                    emitInst(self, LirInst{ .check_optional = .{ .value = cond_temp, .result = has_val } });
                    cond_temp = has_val;
                }
            }
        }
        emitInst(self, LirInst{ .branch = .{ .cond = cond_temp, .then_bb = body_bb, .else_bb = exit_bb } });
        self.current_bb = body_bb;
        self.block_terminated = @intCast(u8, 0);
        if (ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
            var wcap_idx = ast_mod.astStoreNodePayload(store, node_idx);
            var wcapn = ast_mod.astStoreNodeAt(self.ctx.store, wcap_idx);
            if (wcapn.kind == AstKind.while_capture) {
                var wck_tid = getTempType(self, cond_temp);
                var wck_kind: u32 = @intCast(u32, 0);
                if (@intCast(usize, wck_tid) < self.ctx.registry.types_len) { wck_kind = @intCast(u32, @enumToInt(self.ctx.registry.types_items[@intCast(usize, wck_tid)].kind)); }
                var wck_m: []const u8 = "WCAPKIND:"; pal.markerWriteInt(wck_m, wck_kind);
                bindOptionalCapture(self, wcap_idx, orig_cond_temp);
            }
        }
        var wbt_m: []const u8 = "WBT:"; pal.markerWrite(wbt_m);
        lowerStmtBody(self, node.child_1);
        var wbk_m: []const u8 = "WBK:"; pal.markerWrite(wbk_m);
        var wbk_bb: [10]u8 = undefined; var wbk_bl = itoa_mod.itoa(body_bb, wbk_bb[0..]); var wbk_bs: usize = @intCast(usize, 9) - @intCast(usize, wbk_bl); pal.markerWrite(wbk_bb[wbk_bs..@intCast(usize, 9)]);
        var wbk_cb: [10]u8 = undefined; var wbk_cl = itoa_mod.itoa(self.current_bb, wbk_cb[0..]); var wbk_cs: usize = @intCast(usize, 9) - @intCast(usize, wbk_cl); pal.markerWrite(wbk_cb[wbk_cs..@intCast(usize, 9)]);
        var wbk_t: []const u8 = "t"; pal.markerWrite(wbk_t);
        var wbk_tb: [5]u8 = undefined; var wbk_tl = itoa_mod.itoa(@intCast(u32, self.block_terminated), wbk_tb[0..]); var wbk_ts: usize = @intCast(usize, 4) - @intCast(usize, wbk_tl); pal.markerWrite(wbk_tb[wbk_ts..@intCast(usize, 4)]);
        var wbk_nl: []const u8 = "\n"; pal.markerWrite(wbk_nl);
        if (self.block_terminated == @intCast(u8, 0)) {
            var wek_m: []const u8 = "WEK:"; pal.markerWrite(wek_m);
            var wek_nl: []const u8 = "\n"; pal.markerWrite(wek_nl);
            emitInst(self, LirInst{ .jump = cont_bb });
        }
        self.current_bb = cont_bb;
        self.block_terminated = @intCast(u8, 0);
        var inc_m: []const u8 = "INC:c"; pal.markerWrite(inc_m);
        var inc_cb: [10]u8 = undefined; var inc_cl = itoa_mod.itoa(node.child_2, inc_cb[0..]); var inc_cs: usize = @intCast(usize, 9) - @intCast(usize, inc_cl); pal.markerWrite(inc_cb[inc_cs..@intCast(usize, 9)]);
        var inc_nm: []const u8 = "n"; pal.markerWrite(inc_nm);
        var inc_nb: [10]u8 = undefined; var inc_nl2 = itoa_mod.itoa(node_idx, inc_nb[0..]); var inc_ns2: usize = @intCast(usize, 9) - @intCast(usize, inc_nl2); pal.markerWrite(inc_nb[inc_ns2..@intCast(usize, 9)]);
        var inc_nl: []const u8 = "\n"; pal.markerWrite(inc_nl);
        if (node.child_2 != @intCast(u32, 0)) {
            lowerStmtBody(self, node.child_2);
        }
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = cond_bb });
        }
        self.current_bb = exit_bb;
        self.block_terminated = @intCast(u8, 0);
        self.capture_shadow.count = @intCast(usize, 0);
        self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
     } else if (node.kind == AstKind.for_stmt) {
          var forx_m: []const u8 = "FORX\n"; pal.markerWrite(forx_m);
          var pattern = ast_mod.astStoreNodeAt(store, node.child_0);
          var elem_type: [1]u32 = [1]u32{type_mod.TYPE_U32};
           var pat_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
           var a6_m: []const u8 = "A6:"; pal.markerWrite(a6_m);
           var a6_cb: [20]u8 = undefined; var a6_cl = itoa_mod.itoa(node.child_0, a6_cb[0..]); var a6_cs: usize = @intCast(usize, 19) - @intCast(usize, a6_cl); pal.markerWrite(a6_cb[a6_cs..@intCast(usize, 19)]);
           if (pat_type) |pt| {
               var a6_hm: []const u8 = "H"; pal.markerWrite(a6_hm);
               var a6_hb: [20]u8 = undefined; var a6_hl = itoa_mod.itoa(pt, a6_hb[0..]); var a6_hs: usize = @intCast(usize, 19) - @intCast(usize, a6_hl); pal.markerWrite(a6_hb[a6_hs..@intCast(usize, 19)]);
              var pt_ty = self.ctx.registry.types_items[@intCast(usize, pt)];
              if (pt_ty.kind == type_mod.TypeKind.slice_type) {
                  var sp = self.ctx.registry.slice_items[@intCast(usize, pt_ty.payload_idx)];
                  elem_type[0] = sp.elem;
              } else if (pt_ty.kind == type_mod.TypeKind.array_type) {
                  var ap = self.ctx.registry.array_items[@intCast(usize, pt_ty.payload_idx)];
                  elem_type[0] = ap.elem;
              }
           } else {
               var a6_mm: []const u8 = "M"; pal.markerWrite(a6_mm);
           }
            if (pattern.kind == AstKind.range_exclusive or pattern.kind == AstKind.range_inclusive) {
                var start_temp = lowerExpr(self, pattern.child_0);
                var cap_type = if (pat_type) |pt| pt else type_mod.TYPE_U32;
                var end_temp = lowerExpr(self, pattern.child_1);
                if (ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
                    var fcapr = maybeDisambiguateCapture(self, ast_mod.astStoreNodePayload(store, node_idx), cap_type); addLocalDecl(self, fcapr, cap_type, start_temp, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1)); emitInst(self, LirInst{ .decl_local = .{ .name_id = fcapr, .type_id = cap_type, .temp = start_temp } });
                }
            var cond_bb = createBlock(self);
            var body_bb = createBlock(self);
            var exit_bb = createBlock(self);
            var loop_info = LoopInfo{ .header_bb = cond_bb, .exit_bb = exit_bb, .scope_depth = self.scope_depth, .label_id = self.current_label, .is_loop = @intCast(u8, 1) };
            loopInfoArrayListAppend(&self.loop_stack, loop_info);
            emitInst(self, LirInst{ .jump = cond_bb });
            self.current_bb = cond_bb;
            var cmp_op = if (pattern.kind == AstKind.range_inclusive) BIN_LE else BIN_LT;
            var cmp_temp = nextTemp(self, type_mod.TYPE_BOOL);
            emitInst(self, LirInst{ .binary = .{ .op = cmp_op, .lhs = start_temp, .rhs = end_temp, .result = cmp_temp } });
            emitInst(self, LirInst{ .branch = .{ .cond = cmp_temp, .then_bb = body_bb, .else_bb = exit_bb } });
            self.current_bb = body_bb;
            self.block_terminated = @intCast(u8, 0);
            var fbr_m: []const u8 = "FBR:"; pal.markerWrite(fbr_m);
            lowerStmtBody(self, node.child_1);
            if (self.block_terminated == @intCast(u8, 0)) {
                var fbi_m: []const u8 = "FBI:n"; pal.markerWrite(fbi_m);
                var fbi_nb: [10]u8 = undefined; var fbi_nl = itoa_mod.itoa(node.child_1, fbi_nb[0..]); var fbi_ns: usize = @intCast(usize, 9) - @intCast(usize, fbi_nl); pal.markerWrite(fbi_nb[fbi_ns..@intCast(usize, 9)]);
                var fbi_nl2: []const u8 = "\n"; pal.markerWrite(fbi_nl2);
                var one_r = nextTemp(self, type_mod.TYPE_U32);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 1), .result = one_r } });
                var nxt = nextTemp(self, type_mod.TYPE_U32);
                var instc_fr_m: []const u8 = "INSTC:flr\n"; pal.markerWrite(instc_fr_m);
                emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = start_temp, .rhs = one_r, .result = nxt } });
                emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = start_temp, .src = nxt } });
                start_temp = nxt;
                emitInst(self, LirInst{ .jump = cond_bb });
            }
            self.current_bb = exit_bb;
            self.block_terminated = @intCast(u8, 0);
            self.capture_shadow.count = @intCast(usize, 0);
            self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
        } else {
            var slice_temp = lowerExpr(self, node.child_0);
            var ptr_temp = nextTemp(self, type_mod.typeRegistryGetOrCreatePtr(self.ctx.registry, elem_type[0], false));
            var len_temp = nextTemp(self, type_mod.TYPE_USIZE);
            if (pat_type) |pt2| {
                var pt_ty2 = self.ctx.registry.types_items[@intCast(usize, pt2)];
                if (pt_ty2.kind == type_mod.TypeKind.array_type) {
                    var ap2 = self.ctx.registry.array_items[@intCast(usize, pt_ty2.payload_idx)];
                    ptr_temp = slice_temp;
                    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, ap2.length), .result = len_temp } });
                } else {
                    var ms_nid = nameMapGet(self, slice_temp);
                    emitInst(self, LirInst{ .load_field = .{ .name_id = ms_nid, .base = slice_temp, .field_id = type_mod.SLICE_FIELD_PTR, .result = ptr_temp } });
                    emitInst(self, LirInst{ .load_field = .{ .name_id = ms_nid, .base = slice_temp, .field_id = type_mod.SLICE_FIELD_LEN, .result = len_temp } });
                }
            } else {
                var ms_nid = nameMapGet(self, slice_temp);
                emitInst(self, LirInst{ .load_field = .{ .name_id = ms_nid, .base = slice_temp, .field_id = type_mod.SLICE_FIELD_PTR, .result = ptr_temp } });
                emitInst(self, LirInst{ .load_field = .{ .name_id = ms_nid, .base = slice_temp, .field_id = type_mod.SLICE_FIELD_LEN, .result = len_temp } });
            }
            var idx_temp = nextTemp(self, type_mod.TYPE_USIZE);
            emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = idx_temp } });
            var cond_bb = createBlock(self);
            var body_bb = createBlock(self);
            var exit_bb = createBlock(self);
            var loop_info = LoopInfo{ .header_bb = cond_bb, .exit_bb = exit_bb, .scope_depth = self.scope_depth, .label_id = self.current_label, .is_loop = @intCast(u8, 1) };
            loopInfoArrayListAppend(&self.loop_stack, loop_info);
            emitInst(self, LirInst{ .jump = cond_bb });
            self.current_bb = cond_bb;
            var cmp_temp = nextTemp(self, type_mod.TYPE_BOOL);
            emitInst(self, LirInst{ .binary = .{ .op = BIN_LT, .lhs = idx_temp, .rhs = len_temp, .result = cmp_temp } });
            emitInst(self, LirInst{ .branch = .{ .cond = cmp_temp, .then_bb = body_bb, .else_bb = exit_bb } });
            self.current_bb = body_bb;
            var item_temp = nextTemp(self, elem_type[0]);
            emitInst(self, LirInst{ .load_index = .{ .name_id = @intCast(u32, 0), .base = ptr_temp, .index = idx_temp, .result = item_temp } });
            if (ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) { var fcaps = maybeDisambiguateCapture(self, ast_mod.astStoreNodePayload(store, node_idx), elem_type[0]); addLocalDecl(self, fcaps, elem_type[0], item_temp, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1)); emitInst(self, LirInst{ .decl_local = .{ .name_id = fcaps, .type_id = elem_type[0], .temp = item_temp } }); }
            if (node.child_2 != @intCast(u32, 0)) { var icaps = maybeDisambiguateCapture(self, node.child_2, type_mod.TYPE_USIZE); addLocalDecl(self, icaps, type_mod.TYPE_USIZE, idx_temp, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1)); emitInst(self, LirInst{ .decl_local = .{ .name_id = icaps, .type_id = type_mod.TYPE_USIZE, .temp = idx_temp } }); }
            self.block_terminated = @intCast(u8, 0);
            lowerStmtBody(self, node.child_1);
            if (self.block_terminated == @intCast(u8, 0)) {
                var one_s = nextTemp(self, type_mod.TYPE_USIZE);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 1), .result = one_s } });
                var nxt_idx = nextTemp(self, type_mod.TYPE_USIZE);
                var instc_fs_m: []const u8 = "INSTC:fls\n"; pal.markerWrite(instc_fs_m);
                emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = idx_temp, .rhs = one_s, .result = nxt_idx } });
                emitInst(self, LirInst{ .assign = .{ .name_id = @intCast(u32, 0), .dst = idx_temp, .src = nxt_idx } });
                idx_temp = nxt_idx;
                emitInst(self, LirInst{ .jump = cond_bb });
            }
            self.current_bb = exit_bb;
            self.capture_shadow.count = @intCast(usize, 0);
            self.loop_stack.len = self.loop_stack.len - @intCast(usize, 1);
         }
     } else if (node.kind == AstKind.swt_ex) {
         var swt_m: []const u8 = "SWT:s\n"; pal.markerWrite(swt_m);
         var swtn_m: []const u8 = "SWT:n"; pal.markerWriteInt(swtn_m, node_idx);
          var cond_temp = lowerExpr(self, node.child_0);
          var tu_base_box2: [1]u32 = [1]u32{cond_temp};
          var tu_type_box2: [1]u32 = [1]u32{@intCast(u32, 0)};
          var cond_ty_id = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
          if (cond_ty_id) |ct| {
              var ct_ty = self.ctx.registry.types_items[@intCast(usize, ct)];
              if (ct_ty.kind == type_mod.TypeKind.tagged_union_type) {
                  tu_type_box2[0] = ct;
                 var tag_temp = nextTemp(self, type_mod.TYPE_U32);
                var tgn2 = nameMapGet(self, cond_temp);
                emitInst(self, LirInst{ .load_field = .{ .name_id = tgn2, .base = cond_temp, .field_id = type_mod.TU_FIELD_TAG, .result = tag_temp } });
                cond_temp = tag_temp;
            }
         }
        var prong_ec = ast_mod.astStoreNodeExtraChildren(store, node_idx);
        var switch_bb = self.current_bb;
        var prong_start = @intCast(u32, self.func.blocks.len);
        var pi: usize = 0;
        while (pi < prong_ec.len) : (pi += 1) { _ = createBlock(self); }
        var else_bb = createBlock(self);
        var exit_bb = createBlock(self);
        var cases_start = @intCast(u32, self.func.switch_cases.len);
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = ast_mod.astStoreNodeAt(store, prong_ec[pi]);
            if ((prong_node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) { continue; }
            var prong_bb_id = prong_start + @intCast(u32, pi);
            var case_ec = ast_mod.astStoreNodeExtraChildren(store, prong_ec[pi]);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                lowerAppendSwitchCaseItem(self, case_ec[ci], prong_bb_id, cond_ty_id);
            }
        }
        var sc_len = @intCast(u32, self.func.switch_cases.len);
        var cases_count: u32 = sc_len - cases_start;
        var else_target = else_bb;
        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
            var prong_node = ast_mod.astStoreNodeAt(store, prong_ec[pi]);
            if ((prong_node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) {
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
        var exit_preds: u32 = @intCast(u32, 0);

        pi = 0;
        while (pi < prong_ec.len) : (pi += 1) {
             var prong_node = ast_mod.astStoreNodeAt(store, prong_ec[pi]);
             var prong_bb_id = prong_start + @intCast(u32, pi);
             self.current_bb = prong_bb_id;
             self.block_terminated = @intCast(u8, 0);
             if ((prong_node.flags & @intCast(u8, 16)) != @intCast(u8, 0)) {
                 var capture_name = prong_node.child_1;
                 if (tu_type_box2[0] != @intCast(u32, 0)) {
                     var scap2_n: []const u8 = "SCAP2:n"; pal.markerWriteInt(scap2_n, capture_name);
                     var tu_ty2 = self.ctx.registry.types_items[@intCast(usize, tu_type_box2[0])];
                     var tp2 = self.ctx.registry.tu_items[@intCast(usize, tu_ty2.payload_idx)];
                     var case_ec2 = ast_mod.astStoreNodeExtraChildren(store, prong_ec[pi]);
                     if (case_ec2.len > @intCast(usize, 0)) {
                         var ev4 = hash_mod.u32ToU32MapGet(self.ctx.enum_value_table, case_ec2[0]);
                         if (ev4) |idx| {
                             var fe2: type_mod.FieldEntry = self.ctx.registry.fe_items[@intCast(usize, tp2.fields_start) + @intCast(usize, idx)];
                              capture_name = maybeDisambiguateCapture(self, capture_name, fe2.type_id);
                              var payload_temp2 = nextTemp(self, fe2.type_id);
                             _ = hash_mod.u32ToU32MapPut(&self.func.temp_variant_sub_field, payload_temp2, @intCast(u32, 0));
                              emitInst(self, LirInst{ .load_field = .{ .name_id = @intCast(u32, 0), .base = tu_base_box2[0], .field_id = type_mod.TU_FIELD_PAYLOAD, .result = payload_temp2 } });
                              addLocalDecl(self, capture_name, fe2.type_id, payload_temp2, self.scope_depth + @intCast(u32, 1), @intCast(u8, 1));
                              emitInst(self, LirInst{ .decl_local = .{ .name_id = capture_name, .type_id = fe2.type_id, .temp = payload_temp2 } });
                              var scap2_d: []const u8 = "SCAP2:d"; pal.markerWriteInt(scap2_d, capture_name);
                          }
                      } else {
                          addLocalDecl(self, capture_name, tu_type_box2[0], tu_base_box2[0], self.scope_depth + @intCast(u32, 1), @intCast(u8, 1));
                          emitInst(self, LirInst{ .decl_local = .{ .name_id = capture_name, .type_id = tu_type_box2[0], .temp = tu_base_box2[0] } });
                      }
                  }
              }
              lowerStmtBody(self, prong_node.child_0);
            if (self.block_terminated == @intCast(u8, 0)) {
                exit_preds += @intCast(u32, 1);
                emitInst(self, LirInst{ .jump = exit_bb });
            }

            self.capture_shadow.count = @intCast(usize, 0);
        }
        var swx_p: []const u8 = "SWEXIT:preds"; pal.markerWriteInt(swx_p, exit_preds);
        var swx_b: []const u8 = "SWEXIT:bt"; pal.markerWriteInt(swx_b, @intCast(u32, self.block_terminated));
        self.current_bb = exit_bb;
        self.block_terminated = @intCast(u8, 0);
    } else if (node.kind == AstKind.return_stmt) {
        var pre_defer_bb = self.current_bb;
        var pre_defer_blk_p = &self.func.blocks.items[@intCast(usize, pre_defer_bb)];
        var pre_defer_len: usize = pre_defer_blk_p.insts.len;
        expandDefers(self, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 0));
        var post_defer_len: usize = pre_defer_blk_p.insts.len;
        var defer_bb_unchanged: u8 = @intCast(u8, 0);
        if (self.current_bb == pre_defer_bb) {
            defer_bb_unchanged = @intCast(u8, 1);
        }
        if (self.block_terminated == @intCast(u8, 0)) {
            if (node.child_0 != 0) {
                var val = lowerExpr(self, node.child_0);
                var retm: []const u8 = "RET:v="; pal.markerWrite(retm); dbgPrintU32(val); var rett: []const u8 = " t="; pal.markerWrite(rett); dbgPrintU32(self.hoisted_temps.items[@intCast(usize, val)].type_id); var retn: []const u8 = "\n"; pal.markerWrite(retn);
                if (self.func.return_type != type_mod.TYPE_VOID) {
                    var vt = getTempType(self, val);
                    if (vt != self.func.return_type) {
                        var rgm: []const u8 = "RET_GAP:n"; pal.markerWriteInt(rgm, node.child_0);
                        var rgvm: []const u8 = "RET_GAP:v"; pal.markerWriteInt(rgvm, vt);
                        var rgfm: []const u8 = "RET_GAP:f"; pal.markerWriteInt(rgfm, self.func.return_type);
                    }
                    self.hoisted_temps.items[@intCast(usize, val)].type_id = self.func.return_type;
                }
                if (self.func.is_extern == @intCast(u8, 0)) {
                    var tci = findTailCall(self, val);
                    if (tci) |ci| {
                        if (ci.is_self == @intCast(u8, 1) and ci.args_count == @intCast(u32, self.func.params.len)) {
                            if (defer_bb_unchanged == @intCast(u8, 1)) {
                                var di: usize = pre_defer_len;
                                while (di < post_defer_len) : (di += @intCast(usize, 1)) {
                                    pre_defer_blk_p.insts.items[di] = LirInst{ .nop = {} };
                                }
                            }
                            if (hasOtherConsumers(self, ci.result, val)) {
                                {}
                            } else {
                                zeroCallCFG(self, ci, val);
                                var saved_bb = self.current_bb;
                                if (ci.call_block_idx != saved_bb) {
                                    self.current_bb = ci.call_block_idx;
                                }
                                var pi: usize = @intCast(usize, 0);
                                while (pi < self.func.params.len) : (pi += @intCast(usize, 1)) {
                                    emitInst(self, LirInst{ .assign = .{ .name_id = self.func.params.items[pi].name_id, .dst = self.func.params.items[pi].temp_id, .src = ci.args_start + @intCast(u32, pi) } });
                                }
                                emitInst(self, LirInst{ .jump = @intCast(u32, 0) });
                                self.current_bb = saved_bb;
                                self.block_terminated = @intCast(u8, 1);
                            }
                        } else if (ci.is_self == @intCast(u8, 0) and ci.return_type == self.func.return_type) {
                            if (hasOtherConsumers(self, ci.result, val)) {
                                {}
                            } else {
                                zeroCallCFG(self, ci, val);
                                var saved_bb = self.current_bb;
                                if (ci.call_block_idx != saved_bb) {
                                    self.current_bb = ci.call_block_idx;
                                }
                                var tc_slot = lir_mod.lirSideAppendTailCall(self.func, .{ .callee = ci.callee, .module_id = ci.module_id, .args_start = ci.args_start, .args_count = ci.args_count, .result = ci.result, .return_type = ci.return_type, .is_indirect = ci.is_indirect, .is_extern = ci.is_extern });
                                emitInst(self, LirInst{ .tail_call = tc_slot });
                                self.current_bb = saved_bb;
                                self.block_terminated = @intCast(u8, 1);
                            }
                        }
                    }
                }
                if (self.block_terminated == @intCast(u8, 0)) {
                    emitInst(self, LirInst{ .ret = val });
                }
            } else {
                emitValuelessReturn(self);
            }
            self.block_terminated = @intCast(u8, 1);
        }
    } else if (node.kind == AstKind.break_stmt) {
        if (self.loop_stack.len == @intCast(usize, 0)) { return; }
        var label_id: u32 = ast_mod.astStoreNodePayload(store, node_idx);
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
        expandDefers(self, exit_scope, @intCast(u8, 0), @intCast(u8, 0));
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = exit_target });
            self.block_terminated = @intCast(u8, 1);
        }
    } else if (node.kind == AstKind.continue_stmt) {
        if (self.loop_stack.len == @intCast(usize, 0)) { return; }
        var label_id: u32 = ast_mod.astStoreNodePayload(store, node_idx);
        var header_target: u32 = @intCast(u32, 0);
        var cont_scope: u32 = @intCast(u32, 0);
        if (label_id == @intCast(u32, 0)) {
            var si: usize = self.loop_stack.len;
            while (si > @intCast(usize, 0)) : (si -= @intCast(usize, 1)) {
                var li = self.loop_stack.items[si - @intCast(usize, 1)];
                if (li.is_loop != @intCast(u8, 0)) {
                    header_target = li.header_bb;
                    cont_scope = li.scope_depth + @intCast(u32, 1);
                    break;
                }
            }
            if (header_target == @intCast(u32, 0)) { return; }
        } else {
            var si: usize = self.loop_stack.len;
            while (si > @intCast(usize, 0)) : (si -= @intCast(usize, 1)) {
                var li = self.loop_stack.items[si - @intCast(usize, 1)];
                if (li.is_loop != @intCast(u8, 0)) {
                    if (li.label_id == label_id) {
                        header_target = li.header_bb;
                        cont_scope = li.scope_depth + @intCast(u32, 1);
                        break;
                    }
                }
            }
            if (header_target == @intCast(u32, 0)) { return; }
        }
        expandDefers(self, cont_scope, @intCast(u8, 0), @intCast(u8, 0));
        if (self.block_terminated == @intCast(u8, 0)) {
            emitInst(self, LirInst{ .jump = header_target });
            self.block_terminated = @intCast(u8, 1);
        }
    } else if (node.kind == AstKind.var_decl) {
        var name_id: u32 = ast_mod.astStoreNodePayload(store, node_idx);
        var c_name_id = name_id;
        var type_rename: u8 = @intCast(u8, 0);
        var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        if (node.child_0 != 0) {
            var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_0);
            if (rt) |t| { decl_type = t; var vc: []const u8 = "VC"; pal.markerWrite(vc);
            var vdt_m: []const u8 = "VDT:c"; pal.markerWrite(vdt_m);
            var vdt_cb: [10]u8 = undefined; var vdt_cl = itoa_mod.itoa(node.child_0, vdt_cb[0..]); var vdt_cs: usize = @intCast(usize, 9) - @intCast(usize, vdt_cl); pal.markerWrite(vdt_cb[vdt_cs..@intCast(usize, 9)]);
            var vdt_tm: []const u8 = "T"; pal.markerWrite(vdt_tm);
            var vdt_tb: [10]u8 = undefined; var vdt_tl = itoa_mod.itoa(t, vdt_tb[0..]); var vdt_ts: usize = @intCast(usize, 9) - @intCast(usize, vdt_tl); pal.markerWrite(vdt_tb[vdt_ts..@intCast(usize, 9)]);
            var vdt_nl: []const u8 = "\n"; pal.markerWrite(vdt_nl);
            }
            else { var vf: []const u8 = "VF"; pal.markerWrite(vf);
            var lrgm: []const u8 = "LRG:"; pal.markerWrite(lrgm);
            var lrgb: [10]u8 = undefined; var lrgl = itoa_mod.itoa(node.child_0, lrgb[0..]); var lrgs: usize = @intCast(usize, 9) - @intCast(usize, lrgl); pal.markerWrite(lrgb[lrgs..@intCast(usize, 9)]);
            var lrgn: []const u8 = ":0\n"; pal.markerWrite(lrgn);
             }
        } else if (node.child_1 != 0) {
            var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node.child_1);
            if (rt) |t| { decl_type = t; }
        }
        if (self.local_decl_count > @intCast(usize, 0)) {
            var scli: usize = @intCast(usize, 0);
            while (scli < self.local_decl_count) : (scli += @intCast(usize, 1)) {
                if (self.local_decl_names[scli] == name_id and self.local_decl_scopes[scli] <= self.scope_depth and self.local_decl_is_capture[scli] != @intCast(u8, 0)) {
                    c_name_id = synthName(self, name_id);
                    _ = hash_mod.u32ToU32MapPut(&self.capture_shadow, name_id, c_name_id);
                    break;
                }
                if (self.local_decl_names[scli] == name_id and self.local_decl_fn[scli] == self.fn_seq and self.local_decl_types[scli] != decl_type) {
                    c_name_id = synthName(self, name_id);
                    type_rename = @intCast(u8, 1);
                    break;
                }
            }
        }
        if (decl_type == type_mod.TYPE_VOID) {
            var instb_vd_m: []const u8 = "INSTB:vd\n"; pal.markerWrite(instb_vd_m);
            var vfvd_m: []const u8 = "VFLOW:vdecl\n"; pal.markerWrite(vfvd_m);
        }
        if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED)) {
            var dty = self.ctx.registry.types_items[@intCast(usize, decl_type)];
            if (dty.kind == type_mod.TypeKind.fn_type or dty.kind == type_mod.TypeKind.module_type) {
                var vb: []const u8 = "VB"; pal.markerWrite(vb);
            } else {
            var dl_temp = nextTemp(self, decl_type);
            emitInst(self, LirInst{ .decl_local = .{ .name_id = c_name_id, .type_id = decl_type, .temp = dl_temp } });
            if (type_rename != @intCast(u8, 0)) {
                addLocalDeclRenamed(self, name_id, c_name_id, decl_type, dl_temp, self.scope_depth, @intCast(u8, 0));
            } else {
                addLocalDecl(self, c_name_id, decl_type, dl_temp, self.scope_depth, @intCast(u8, 0));
            }
            if (node.child_1 != 0) {
                var init_node = ast_mod.astStoreNodeAt(store, node.child_1);
                var is_array_type: u8 = @intCast(u8, 0);
                var dt2 = self.ctx.registry.types_items[@intCast(usize, decl_type)];
                if (dt2.kind == type_mod.TypeKind.array_type) is_array_type = @intCast(u8, 1);
                if (is_array_type == @intCast(u8, 1) and (init_node.kind == AstKind.array_init or init_node.kind == AstKind.tuple_literal)) {
                    var arr_temp = lowerExpr(self, node.child_1);
                    emitInst(self, LirInst{ .assign = .{ .name_id = c_name_id, .dst = dl_temp, .src = arr_temp } });
                } else if (init_node.kind == AstKind.undefined_literal) {
                    var arr_temp = nextTemp(self, decl_type);
                    if (is_array_type == @intCast(u8, 1) or self.ctx.safe_checks) {
                        emitInst(self, LirInst{ .undefined_const = .{ .result = arr_temp, .type_id = decl_type } });
                    }
                    emitInst(self, LirInst{ .assign = .{ .name_id = c_name_id, .dst = dl_temp, .src = arr_temp } });
                } else {
                    if (decl_type == type_mod.TYPE_VOID) {
                        var t4u_vi_m: []const u8 = "T4U:vI\n"; pal.markerWrite(t4u_vi_m);
                    }
                    var sn_x: u8 = @intCast(u8, 0);
                    if (decl_type != type_mod.TYPE_VOID and decl_type != type_mod.TYPE_UNDEFINED) {
                        var dt_x = self.ctx.registry.types_items[@intCast(usize, decl_type)];
                        if (dt_x.kind == type_mod.TypeKind.optional_type and node.child_1 != 0) {
                            var in_x = ast_mod.astStoreNodeAt(store, node.child_1);
                            if (in_x.kind == AstKind.null_literal) {
                                emitInst(self, LirInst{ .set_optional_null = .{ .result = dl_temp, .type_id = decl_type } });
                                sn_x = @intCast(u8, 1);
                            }
                        }
                    }
                    if (sn_x == @intCast(u8, 0)) {
                    var init_val = lowerExpr(self, node.child_1);

                    if (decl_type != type_mod.TYPE_VOID) {
                    emitInst(self, LirInst{ .assign = .{ .name_id = c_name_id, .dst = dl_temp, .src = init_val } });
                    var reg: u32 = @intCast(u32, 0);
                    if (findLocalTemp(self, c_name_id)) |r| { reg = r; }
                    var vds_m: []const u8 = "VDS:n"; pal.markerWrite(vds_m);
                    var vds_nb: [10]u8 = undefined; var vds_nl = itoa_mod.itoa(name_id, vds_nb[0..]); var vds_ns: usize = @intCast(usize, 9) - @intCast(usize, vds_nl); pal.markerWrite(vds_nb[vds_ns..@intCast(usize, 9)]);
                    var vds_tm: []const u8 = "t"; pal.markerWrite(vds_tm);
                    var vds_tb: [10]u8 = undefined; var vds_tl = itoa_mod.itoa(decl_type, vds_tb[0..]); var vds_ts: usize = @intCast(usize, 9) - @intCast(usize, vds_tl); pal.markerWrite(vds_tb[vds_ts..@intCast(usize, 9)]);
                    var vds_dm: []const u8 = "d"; pal.markerWrite(vds_dm);
                    var vds_db: [10]u8 = undefined; var vds_dl = itoa_mod.itoa(dl_temp, vds_db[0..]); var vds_ds: usize = @intCast(usize, 9) - @intCast(usize, vds_dl); pal.markerWrite(vds_db[vds_ds..@intCast(usize, 9)]);
                    var vds_rm: []const u8 = "r"; pal.markerWrite(vds_rm);
                    var vds_rb: [10]u8 = undefined; var vds_rl = itoa_mod.itoa(reg, vds_rb[0..]); var vds_rs: usize = @intCast(usize, 9) - @intCast(usize, vds_rl); pal.markerWrite(vds_rb[vds_rs..@intCast(usize, 9)]);
                    var vds_vm: []const u8 = "v"; pal.markerWrite(vds_vm);
                    var vds_vb: [10]u8 = undefined; var vds_vl = itoa_mod.itoa(init_val, vds_vb[0..]); var vds_vs: usize = @intCast(usize, 9) - @intCast(usize, vds_vl); pal.markerWrite(vds_vb[vds_vs..@intCast(usize, 9)]);
                    var vds_nl2: []const u8 = "\n"; pal.markerWrite(vds_nl2);
                    }
                    }
                }
            }
            }
        } else {
            var und: []const u8 = "NU";
            pal.markerWrite(und);
            if (node.child_1 != @intCast(u32, 0)) {
                var und2: []const u8 = "I";
                pal.markerWrite(und2);
                var init_node = ast_mod.astStoreNodeAt(store, node.child_1);
                if (init_node.kind == AstKind.array_init) { var dk2: []const u8 = "a"; pal.markerWrite(dk2); }
                else if (init_node.kind == AstKind.struct_init) { var dk2: []const u8 = "s"; pal.markerWrite(dk2); }
                else { var dk2: []const u8 = "o"; pal.markerWrite(dk2); }
            }
            if (node.child_0 != @intCast(u32, 0)) {
                var und3: []const u8 = "T";
                pal.markerWrite(und3);
            }
            var und4: []const u8 = " ";
            pal.markerWrite(und4);
        }
    } else if (node.kind == AstKind.add_assign) {
        var ade_m: []const u8 = "ADE:p\n"; pal.markerWrite(ade_m);
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_ADD, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_ADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        var bio_m: []const u8 = "BIO:r"; pal.markerWrite(bio_m);
        var bio_rb: [10]u8 = undefined; var bio_rl = itoa_mod.itoa(op_r, bio_rb[0..]); var bio_rs: usize = @intCast(usize, 9) - @intCast(usize, bio_rl); pal.markerWrite(bio_rb[bio_rs..@intCast(usize, 9)]);
        var bio_om: []const u8 = "o"; pal.markerWrite(bio_om);
        var bio_ob: [10]u8 = undefined; var bio_ol = itoa_mod.itoa(@intCast(u32, BIN_ADD), bio_ob[0..]); var bio_os: usize = @intCast(usize, 9) - @intCast(usize, bio_ol); pal.markerWrite(bio_ob[bio_os..@intCast(usize, 9)]);
        var bio_nl: []const u8 = "\n"; pal.markerWrite(bio_nl);
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.sub_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_SUB, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.mul_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_MUL, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.wrap_add_assign or node.kind == AstKind.wrap_sub_assign or node.kind == AstKind.wrap_mul_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        if (node.kind == AstKind.wrap_add_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else if (node.kind == AstKind.wrap_sub_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WSUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_WMUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        }
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.sat_add_assign or node.kind == AstKind.sat_sub_assign or node.kind == AstKind.sat_mul_assign or node.kind == AstKind.sat_shl_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        if (node.kind == AstKind.sat_add_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SADD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else if (node.kind == AstKind.sat_sub_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SSUB, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else if (node.kind == AstKind.sat_mul_assign) {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SMUL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        } else {
            emitInst(self, LirInst{ .binary = .{ .op = BIN_SSHL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        }
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.div_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckDivMod(self, lhs_val, rhs_val);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_DIV, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.mod_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckDivMod(self, lhs_val, rhs_val);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_MOD, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.shl_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckShift(self, lhs_val, rhs_val);
        emitSafeCheckOverflow(self, lir_mod.CHECK_OP_SHL, lhs_val, rhs_val, getTempType(self, lhs_val));
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHL, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.shr_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitSafeCheckShift(self, lhs_val, rhs_val);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_SHR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.and_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_AND, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.xor_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_XOR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
    } else if (node.kind == AstKind.or_assign) {
        var lhs_val = lowerExpr(self, node.child_0);
        var rhs_val = lowerExpr(self, node.child_1);
        var op_r_box: [1]u32 = [1]u32{type_mod.TYPE_U32};
        var op_rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (op_rt) |t| { op_r_box[0] = t; }
        if (op_rt == null) { var flb2: []const u8 = "C3opFLB\n"; pal.markerWrite(flb2); }
        var op_r = nextTemp(self, op_r_box[0]);
        emitInst(self, LirInst{ .binary = .{ .op = BIN_OR, .lhs = lhs_val, .rhs = rhs_val, .result = op_r } });
        lowerCompoundLValueStore(self, node_idx, lhs_val, op_r);
      } else if (node.kind == AstKind.expr_stmt) {
          lowerStmtBody(self, node.child_0);
      } else {
          var rpt_m: []const u8 = "RPT:k"; pal.markerWrite(rpt_m);
        var rpt_kb: [10]u8 = undefined;         var rpt_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(node.kind)), rpt_kb[0..]); var rpt_ks: usize = @intCast(usize, 9) - @intCast(usize, rpt_kl); pal.markerWrite(rpt_kb[rpt_ks..@intCast(usize, 9)]);
        var rpt_nm: []const u8 = "n"; pal.markerWrite(rpt_nm);
        var rpt_nb: [10]u8 = undefined; var rpt_nl = itoa_mod.itoa(node_idx, rpt_nb[0..]); var rpt_ns: usize = @intCast(usize, 9) - @intCast(usize, rpt_nl); pal.markerWrite(rpt_nb[rpt_ns..@intCast(usize, 9)]);
        var rpt_nl2: []const u8 = "\n"; pal.markerWrite(rpt_nl2);
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

pub fn expandDefers(self: *LirLowerer, target_depth: u32, is_error_path: u8, pop: u8) void {
    var i = self.defer_stack.len;
    while (i > @intCast(usize, 0)) {
        i -= @intCast(usize, 1);
        var action = self.defer_stack.items[i];
        if (action.scope_depth < target_depth) {
            break;
        }
        if (action.kind == @intCast(u8, 0)) {
            if (pop != @intCast(u8, 0)) {
                self.defer_stack.len = i;
            }
            lowerStmt(self, action.ast_node);
            if (pop != @intCast(u8, 0)) {
                i = self.defer_stack.len;
            }
        } else if (action.kind == @intCast(u8, 1) and is_error_path != @intCast(u8, 0)) {
            if (pop != @intCast(u8, 0)) {
                self.defer_stack.len = i;
            }
            lowerStmt(self, action.ast_node);
            if (pop != @intCast(u8, 0)) {
                i = self.defer_stack.len;
            }
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
        if (td.type_id == type_mod.TYPE_VOID) {
            var t4u_hs_m: []const u8 = "T4U:hS\n"; pal.markerWrite(t4u_hs_m);
            var vfht_m: []const u8 = "VFLOW:htv\n"; pal.markerWrite(vfht_m);
        } else {
        lir_mod.lirInstArrayListAppend(&new_insts, LirInst{
            .decl_temp = .{ .temp = td.temp_id, .type_id = td.type_id },
        });
        }
    }
    var j: usize = 0;
    while (j < entry_bb.insts.len) : (j += 1) {
        lir_mod.lirInstArrayListAppend(&new_insts, entry_bb.insts.items[j]);
    }
    entry_bb.insts.items = new_insts.items;
    entry_bb.insts.len = new_insts.len;
    entry_bb.insts.capacity = new_insts.capacity;
}

fn applyNoneCoercion(self: *LirLowerer, src_temp: u32, coercion: CoercionEntry) u32 {
    var apns_m: []const u8 = "APN:s"; pal.markerWriteInt(apns_m, src_temp);
    var apnt_m: []const u8 = "APN:t"; pal.markerWriteInt(apnt_m, coercion.target_type);
    var apnn_m: []const u8 = "APN:n"; pal.markerWriteInt(apnn_m, coercion.node_idx);
    if (src_temp != 0 and @intCast(usize, src_temp) < self.hoisted_temps.len) {
        var sc_ty = getTempType(self, src_temp);
        var apny_m: []const u8 = "APN:y"; pal.markerWriteInt(apny_m, sc_ty);
        if (sc_ty == type_mod.TYPE_NULL) {
            var tgt = self.ctx.registry.types_items[@intCast(usize, coercion.target_type)];
            if (tgt.kind == type_mod.TypeKind.optional_type) {
                var dst = nextTemp(self, coercion.target_type);
                emitInst(self, LirInst{ .set_optional_null = .{ .result = dst, .type_id = coercion.target_type } });
                var cof5_m: []const u8 = "COF:src"; pal.markerWriteInt(cof5_m, src_temp); var cof5_tm: []const u8 = "T"; pal.markerWriteInt(cof5_tm, coercion.target_type); var cof5_sm: []const u8 = "S"; pal.markerWriteInt(cof5_sm, sc_ty); var cof5_nl: []const u8 = "\n"; pal.markerWrite(cof5_nl); return dst;
            }
            if (type_mod.typeRegistryIsPointer(self.ctx.registry, coercion.target_type) or tgt.kind == type_mod.TypeKind.fn_type) {
                var dst = nextTemp(self, coercion.target_type);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, 0), .result = dst } });
                var cof6_m: []const u8 = "COF:src"; pal.markerWriteInt(cof6_m, src_temp); var cof6_tm: []const u8 = "T"; pal.markerWriteInt(cof6_tm, coercion.target_type); var cof6_sm: []const u8 = "S"; pal.markerWriteInt(cof6_sm, sc_ty); var cof6_nl: []const u8 = "\n"; pal.markerWrite(cof6_nl); return dst;
            }
        }
    }
    return src_temp;
}

pub fn applyCoercion(self: *LirLowerer, src_temp: u32, coercion: CoercionEntry) u32 {
    var kind = coercion.kind;
    if (kind == CoercionKind.none) {
        return applyNoneCoercion(self, src_temp, coercion);
    } else if (kind == CoercionKind.wrap_optional_null) {
        return materializeInto(self, src_temp, coercion.target_type, SrcIntent.null_src);
    } else if (kind == CoercionKind.wrap_optional) {
        return materializeInto(self, src_temp, coercion.target_type, srcIntentFor(self, coercion));
    } else if (kind == CoercionKind.wrap_error_success) {
        return materializeInto(self, src_temp, coercion.target_type, srcIntentFor(self, coercion));
    } else if (kind == CoercionKind.wrap_error_err) {
        return materializeInto(self, src_temp, coercion.target_type, SrcIntent.error_src);
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
        return materializeInto(self, src_temp, coercion.target_type, srcIntentFor(self, coercion));
    } else if (kind == CoercionKind.array_to_slice) {
        var dst = nextTemp(self, coercion.target_type);
        var arr_len: u32 = @intCast(u32, 1);
        if (resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, coercion.node_idx)) |src_tid| {
            var src_t = self.ctx.registry.types_items[@intCast(usize, src_tid)];
            if (src_t.kind == type_mod.TypeKind.ptr_type) {
                var pp = self.ctx.registry.ptr_items[@intCast(usize, src_t.payload_idx)];
                var pointee = self.ctx.registry.types_items[@intCast(usize, pp.base)];
                if (pointee.kind == type_mod.TypeKind.array_type) {
                    arr_len = self.ctx.registry.array_items[@intCast(usize, pointee.payload_idx)].length;
                }
            } else if (src_t.kind == type_mod.TypeKind.array_type) {
                arr_len = self.ctx.registry.array_items[@intCast(usize, src_t.payload_idx)].length;
            }
        }
        var len_temp = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, arr_len), .result = len_temp } });
        emitInst(self, LirInst{ .make_slice = .{ .ptr = src_temp, .len = len_temp, .result = dst, .type_id = coercion.target_type } });
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
        var sllen: u32 = @intCast(u32, 1);
        var slnode = ast_mod.astStoreNodeAt(self.ctx.store, coercion.node_idx);
        if (slnode.kind == AstKind.string_literal) {
            var slstr_id = self.ctx.store.string_values.items[@intCast(usize, ast_mod.astStoreNodePayload(self.ctx.store, coercion.node_idx))];
            var slstr_data = si_mod.stringInternerGet(self.ctx.registry.interner, slstr_id);
            sllen = @intCast(u32, slstr_data.len);
        }
        var sl_len_temp = nextTemp(self, type_mod.TYPE_U32);
        emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, sllen), .result = sl_len_temp } });
        var mks_m: []const u8 = "MKS:r"; pal.markerWrite(mks_m);
        var mks_rb: [10]u8 = undefined; var mks_rl = itoa_mod.itoa(dst, mks_rb[0..]); var mks_rs: usize = @intCast(usize, 9) - @intCast(usize, mks_rl); pal.markerWrite(mks_rb[mks_rs..@intCast(usize, 9)]);
        var mks_nl: []const u8 = "\n"; pal.markerWrite(mks_nl);
        emitInst(self, LirInst{ .make_slice = .{ .ptr = src_temp, .len = sl_len_temp, .result = dst, .type_id = coercion.target_type } });
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

const CallInfo = struct {
    is_self: u8,
    is_indirect: u8,
    is_extern: u8,
    callee: u32,
    module_id: u32,
    args_start: u32,
    args_count: u32,
    result: u32,
    return_type: u32,
    call_block_idx: u32,
    call_inst_idx: u32,
};

fn findTailCall(self: *LirLowerer, ret_temp: u32) ?CallInfo {
    var cur = ret_temp;
    var hops: u32 = @intCast(u32, 0);
    while (hops < @intCast(u32, 5)) : (hops += @intCast(u32, 1)) {
        var found_any: u8 = @intCast(u8, 0);
        var bi: usize = @intCast(usize, 0);
        while (bi < self.func.blocks.len) : (bi += @intCast(usize, 1)) {
            var blk = self.func.blocks.items[bi];
            var ii: usize = @intCast(usize, 0);
            while (ii < blk.insts.len) : (ii += @intCast(usize, 1)) {
                var inst = blk.insts.items[ii];
                var tg = @enumToInt(inst.tag);
                if (tg == @enumToInt(LirInst.call_direct)) {
                    var cd = lir_mod.lirSideGetCallDirect(self.func, inst.call_direct);
                    if (cd.result == cur) {
                        var is_self: u8 = @intCast(u8, 0);
                        if (cd.name_id == self.func.name_id and cd.module_id == self.func.module_id) {
                            is_self = @intCast(u8, 1);
                        }
                        return CallInfo{ .is_self = is_self, .is_indirect = @intCast(u8, 0), .is_extern = cd.is_extern, .callee = cd.name_id, .module_id = cd.module_id, .args_start = cd.args_start, .args_count = cd.args_count, .result = cd.result, .return_type = cd.return_type, .call_block_idx = @intCast(u32, bi), .call_inst_idx = @intCast(u32, ii) };
                    }
                } else if (tg == @enumToInt(LirInst.call)) {
                    if (inst.call.result == cur) {
                        return CallInfo{ .is_self = @intCast(u8, 0), .is_indirect = @intCast(u8, 1), .is_extern = @intCast(u8, 0), .callee = inst.call.callee, .module_id = @intCast(u32, 0), .args_start = inst.call.args_start, .args_count = inst.call.args_count, .result = inst.call.result, .return_type = type_mod.TYPE_UNDEFINED, .call_block_idx = @intCast(u32, bi), .call_inst_idx = @intCast(u32, ii) };
                    }
                } else if (tg == @enumToInt(LirInst.unwrap_error_payload)) {
                    if (inst.unwrap_error_payload.result == cur) {
                        cur = inst.unwrap_error_payload.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                } else if (tg == @enumToInt(LirInst.unwrap_error_code)) {
                    if (inst.unwrap_error_code.result == cur) {
                        return null;
                    }
                } else if (tg == @enumToInt(LirInst.wrap_error_ok)) {
                    if (inst.wrap_error_ok.result == cur) {
                        cur = inst.wrap_error_ok.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                } else if (tg == @enumToInt(LirInst.wrap_error_err)) {
                    if (inst.wrap_error_err.result == cur) {
                        cur = inst.wrap_error_err.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                }
            }
            if (found_any == @intCast(u8, 1)) { break; }
        }
        if (found_any == @intCast(u8, 0)) { return null; }
    }
    return null;
}

fn zeroChainInsts(self: *LirLowerer, ret_temp: u32) void {
    var cur = ret_temp;
    var hops: u32 = @intCast(u32, 0);
    while (hops < @intCast(u32, 5)) : (hops += @intCast(u32, 1)) {
        var found_any: u8 = @intCast(u8, 0);
        var bi: usize = @intCast(usize, 0);
        while (bi < self.func.blocks.len) : (bi += @intCast(usize, 1)) {
            var blk = self.func.blocks.items[bi];
            var ii: usize = @intCast(usize, 0);
            while (ii < blk.insts.len) : (ii += @intCast(usize, 1)) {
                var inst = blk.insts.items[ii];
                var tg = @enumToInt(inst.tag);
                if (tg == @enumToInt(LirInst.unwrap_error_payload)) {
                    if (inst.unwrap_error_payload.result == cur) {
                        blk.insts.items[ii] = LirInst{ .nop = {} };
                        cur = inst.unwrap_error_payload.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                } else if (tg == @enumToInt(LirInst.unwrap_error_code)) {
                    if (inst.unwrap_error_code.result == cur) {
                        blk.insts.items[ii] = LirInst{ .nop = {} };
                        cur = inst.unwrap_error_code.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                } else if (tg == @enumToInt(LirInst.wrap_error_ok)) {
                    if (inst.wrap_error_ok.result == cur) {
                        blk.insts.items[ii] = LirInst{ .nop = {} };
                        cur = inst.wrap_error_ok.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                } else if (tg == @enumToInt(LirInst.wrap_error_err)) {
                    if (inst.wrap_error_err.result == cur) {
                        blk.insts.items[ii] = LirInst{ .nop = {} };
                        cur = inst.wrap_error_err.value;
                        found_any = @intCast(u8, 1);
                        break;
                    }
                }
            }
            if (found_any == @intCast(u8, 1)) { break; }
        }
        if (found_any == @intCast(u8, 0)) { return; }
    }
}

fn hasOtherConsumers(self: *LirLowerer, call_result: u32, ret_temp: u32) bool {
    var bi: usize = @intCast(usize, 0);
    while (bi < self.func.blocks.len) : (bi += @intCast(usize, 1)) {
        var blk = self.func.blocks.items[bi];
        var ii: usize = @intCast(usize, 0);
        while (ii < blk.insts.len) : (ii += @intCast(usize, 1)) {
            var inst = blk.insts.items[ii];
            var tg = @enumToInt(inst.tag);
            if (tg == @enumToInt(LirInst.call_direct) or tg == @enumToInt(LirInst.call) or
                tg == @enumToInt(LirInst.unwrap_error_payload) or tg == @enumToInt(LirInst.unwrap_error_code) or
                tg == @enumToInt(LirInst.wrap_error_ok) or tg == @enumToInt(LirInst.wrap_error_err) or
                tg == @enumToInt(LirInst.check_error) or tg == @enumToInt(LirInst.nop)) {
                {}
            } else if (tg == @enumToInt(LirInst.ret)) {
                if (inst.ret != ret_temp) {
                    {}
                }
            } else if (tg == @enumToInt(LirInst.binary)) {
                if (inst.binary.lhs == call_result or inst.binary.rhs == call_result) return true;
            } else if (tg == @enumToInt(LirInst.unary)) {
                if (inst.unary.operand == call_result) return true;
            } else if (tg == @enumToInt(LirInst.addr_of)) {
                if (inst.addr_of.operand == call_result) return true;
            } else if (tg == @enumToInt(LirInst.load_field)) {
                if (inst.load_field.base == call_result) return true;
            } else if (tg == @enumToInt(LirInst.store_field)) {
                if (inst.store_field.base == call_result or inst.store_field.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.load_bitfield)) {
                if (inst.load_bitfield.base == call_result) return true;
            } else if (tg == @enumToInt(LirInst.store_bitfield)) {
                if (inst.store_bitfield.base == call_result or inst.store_bitfield.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.load_index)) {
                if (inst.load_index.base == call_result or inst.load_index.index == call_result) return true;
            } else if (tg == @enumToInt(LirInst.load)) {
                if (inst.load.ptr == call_result) return true;
            } else if (tg == @enumToInt(LirInst.store)) {
                if (inst.store.ptr == call_result or inst.store.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.assign)) {
                if (inst.assign.src == call_result) return true;
            } else if (tg == @enumToInt(LirInst.assign_field)) {
                if (inst.assign_field.base == call_result or inst.assign_field.src == call_result) return true;
            } else if (tg == @enumToInt(LirInst.assign_index)) {
                if (inst.assign_index.base == call_result or inst.assign_index.index == call_result or inst.assign_index.src == call_result) return true;
            } else if (tg == @enumToInt(LirInst.branch)) {
                if (inst.branch.cond == call_result) return true;
            } else if (tg == @enumToInt(LirInst.switch_br)) {
                if (inst.switch_br.cond == call_result) return true;
            } else if (tg == @enumToInt(LirInst.store_local)) {
                if (inst.store_local.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.store_global)) {
                if (inst.store_global.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.print_val)) {
                if (inst.print_val.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.wrap_optional)) {
                if (inst.wrap_optional.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.unwrap_optional)) {
                if (inst.unwrap_optional.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.check_optional)) {
                if (inst.check_optional.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.int_cast)) {
                if (inst.int_cast.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.float_cast)) {
                if (inst.float_cast.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.ptr_cast)) {
                if (inst.ptr_cast.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.int_to_float)) {
                if (inst.int_to_float.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.ptr_to_int)) {
                if (inst.ptr_to_int.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.int_to_ptr)) {
                if (inst.int_to_ptr.value == call_result) return true;
            } else if (tg == @enumToInt(LirInst.make_slice)) {
                if (inst.make_slice.ptr == call_result or inst.make_slice.len == call_result) return true;
            } else {
                {}
            }
        }
    }
    return false;
}

fn zeroCallCFG(self: *LirLowerer, ci: CallInfo, ret_temp: u32) void {
    var callblk = &self.func.blocks.items[@intCast(usize, ci.call_block_idx)];
    callblk.insts.items[@intCast(usize, ci.call_inst_idx)] = LirInst{ .nop = {} };
    var j1: u32 = ci.call_inst_idx + @intCast(u32, 1);
    if (j1 < @intCast(u32, callblk.insts.len)) {
        var i1 = callblk.insts.items[@intCast(usize, j1)];
        var tg1 = @enumToInt(i1.tag);
        if (tg1 == @enumToInt(LirInst.check_error) or tg1 == @enumToInt(LirInst.check_optional)) {
            callblk.insts.items[@intCast(usize, j1)] = LirInst{ .nop = {} };
        }
    }
    var j2: u32 = ci.call_inst_idx + @intCast(u32, 2);
    if (j2 < @intCast(u32, callblk.insts.len)) {
        var i2 = callblk.insts.items[@intCast(usize, j2)];
        var tg2 = @enumToInt(i2.tag);
        if (tg2 == @enumToInt(LirInst.branch)) {
            callblk.insts.items[@intCast(usize, j2)] = LirInst{ .nop = {} };
        }
    }
    zeroChainInsts(self, ret_temp);
}

fn emitValuelessReturn(self: *LirLowerer) void {
    var rty = self.ctx.registry.types_items[@intCast(usize, self.func.return_type)];
    var evr_rt: []const u8 = "EVR:rt"; pal.markerWriteInt(evr_rt, self.func.return_type);
    var evr_k: []const u8 = "EVR:k"; pal.markerWriteInt(evr_k, @intCast(u32, @enumToInt(rty.kind)));
    if (rty.kind == type_mod.TypeKind.error_union_type) {
        var pay = self.ctx.registry.eu_items[@intCast(usize, rty.payload_idx)].payload;
        var ptmp = nextTemp(self, pay);
        var eures = nextTemp(self, self.func.return_type);
        emitInst(self, LirInst{ .wrap_error_ok = .{ .value = ptmp, .result = eures, .type_id = self.func.return_type } });
        emitInst(self, LirInst{ .ret = eures });
    } else {
        emitInst(self, LirInst{ .ret_void = {} });
    }
}

pub fn lowerFn(self: *LirLowerer, fn_node: u32) LirFunction {
    self.fn_seq = self.fn_seq + @intCast(u32, 1);
    var evcap = self.ctx.enum_value_table.capacity; var evcnt = self.ctx.enum_value_table.count;
    var evcap_buf: [20]u8 = undefined; var evcnt_buf: [20]u8 = undefined;
    var evcap_len = itoa_mod.itoa(@intCast(u32, evcap), evcap_buf[0..]);
    var evcnt_len = itoa_mod.itoa(@intCast(u32, evcnt), evcnt_buf[0..]);
    var evcap_s: usize = @intCast(usize, 19) - @intCast(usize, evcap_len);
    var evcnt_s: usize = @intCast(usize, 19) - @intCast(usize, evcnt_len);
    var lN: []const u8 = "lN="; pal.markerWrite(lN);
    pal.markerWrite(evcnt_buf[evcnt_s..@intCast(usize, 19)]);
    var lC: []const u8 = " lC="; pal.markerWrite(lC);
    pal.markerWrite(evcap_buf[evcap_s..@intCast(usize, 19)]);
    var lnl: []const u8 = "\n"; pal.markerWrite(lnl);
    var store = self.ctx.store;
    var node = ast_mod.astStoreNodeAt(store, fn_node);
    var proto_idx = ast_mod.astStoreNodePayload(store, fn_node);
    var proto = store.fn_protos.items[@intCast(usize, proto_idx)];
    var fnl_m: []const u8 = "FNL:"; pal.markerWriteInt(fnl_m, proto.name_id);
    var func_raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, @sizeOf(LirFunction)), @intCast(usize, 4)) catch unreachable;
    var func_ptr = @ptrCast(*LirFunction, func_raw);
    func_ptr.name_id = proto.name_id;
    func_ptr.module_id = self.module_id;
    var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, proto.return_type_node);
    if (rt) |_| { var dr: []const u8 = "HR"; pal.markerWrite(dr); } else { var dr: []const u8 = "MR"; pal.markerWrite(dr); }
    func_ptr.return_type = if (rt) |tid| tid else type_mod.TYPE_VOID;
    func_ptr.params = lir_mod.lirParamArrayListInit(self.alloc);
    func_ptr.blocks = lir_mod.basicBlockArrayListInit(self.alloc);
    func_ptr.hoisted_temps = lir_mod.tempDeclArrayListInit(self.alloc);
    func_ptr.switch_cases = lir_mod.switchCaseArrayListInit(self.alloc);
    func_ptr.side_table = lir_mod.lirSideEntryArrayListInit(self.alloc);
    func_ptr.temp_variant_sub_field = hash_mod.u32ToU32MapInit(self.alloc);
    func_ptr.is_extern = @intCast(u8, if ((node.flags & @intCast(u8, 0x04)) != 0) 1 else 0);
    func_ptr.is_pub = @intCast(u8, if ((node.flags & @intCast(u8, 0x02)) != 0) 1 else 0);
    func_ptr.is_variadic = @intCast(u8, 0);
    var frt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, fn_node);
    if (frt) |frt_id| {
        var fty = self.ctx.registry.types_items[@intCast(usize, frt_id)];
        if (fty.kind == type_mod.TypeKind.fn_type) {
            var ffp = self.ctx.registry.fn_items[@intCast(usize, fty.payload_idx)];
            if ((ffp.flags_packed & @intCast(u8, 1)) != @intCast(u8, 0)) {
                func_ptr.is_variadic = @intCast(u8, 1);
            }
        }
    }
    if (func_ptr.is_variadic != @intCast(u8, 0) and proto.params_count == @intCast(u16, 0)) {
        var va_msg: []const u8 = "variadic function must have at least one fixed parameter";
        _ = diag_mod.diagnosticCollectorAdd(self.ctx.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3012_VARARGS_INVALID)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), va_msg);
    }
    var p_payload: u64 = (@intCast(u64, proto.params_start) << @intCast(u64, 32)) | @intCast(u64, proto.params_count);
    if (proto.params_count > @intCast(u16, 0)) {
        var pnodes = ast_mod.astStoreGetExtraChildren(store, p_payload);
        var pi: usize = @intCast(usize, 0);
        while (pi < pnodes.len) : (pi += @intCast(usize, 1)) {
            var pnode = ast_mod.astStoreNodeAt(store, pnodes[pi]);
            if (pnode.child_0 != @intCast(u32, 0)) {
                var p_name_id: u32 = ast_mod.astStoreNodePayload(store, pnodes[pi]);
                var p_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, pnode.child_0);
                if (p_type) |_| { var dp: []const u8 = "HP"; pal.markerWrite(dp); } else { var dp: []const u8 = "MP"; pal.markerWrite(dp); }
                var p_tid = if (p_type) |pt| pt else type_mod.TYPE_UNDEFINED;
                var p_temp: u32 = nextTemp(self, type_mod.TYPE_UNDEFINED);
                var und_fp_m: []const u8 = "UND:fpPt"; pal.markerWrite(und_fp_m);
                var und_fp_tb: [10]u8 = undefined; var und_fp_tl = itoa_mod.itoa(p_temp, und_fp_tb[0..]); var und_fp_ts: usize = @intCast(usize, 9) - @intCast(usize, und_fp_tl); pal.markerWrite(und_fp_tb[und_fp_ts..@intCast(usize, 9)]);
                var und_fp_nl: []const u8 = "\n"; pal.markerWrite(und_fp_nl);
                lir_mod.lirParamArrayListAppend(&func_ptr.params, lir_mod.LirParam{
                    .name_id = p_name_id,
                    .type_id = p_tid,
                    .temp_id = p_temp,
                });
                addLocalDecl(self, p_name_id, p_tid, p_temp, self.scope_depth, @intCast(u8, 0));
                self.hoisted_temps.items[@intCast(usize, p_temp)].type_id = p_tid;
                if (p_type) |pt| {
                    var lpf_m: []const u8 = "LPF:n"; pal.markerWrite(lpf_m);
                    var lpf_nb: [10]u8 = undefined; var lpf_nl = itoa_mod.itoa(p_name_id, lpf_nb[0..]); var lpf_ns: usize = @intCast(usize, 9) - @intCast(usize, lpf_nl); pal.markerWrite(lpf_nb[lpf_ns..@intCast(usize, 9)]);
                    var lpf_tm: []const u8 = "t"; pal.markerWrite(lpf_tm);
                    var lpf_tb: [10]u8 = undefined; var lpf_tl = itoa_mod.itoa(pt, lpf_tb[0..]); var lpf_ts: usize = @intCast(usize, 9) - @intCast(usize, lpf_tl); pal.markerWrite(lpf_tb[lpf_ts..@intCast(usize, 9)]);
                    var lpf_pm: []const u8 = "T"; pal.markerWrite(lpf_pm);
                    var lpf_pb: [10]u8 = undefined; var lpf_pl = itoa_mod.itoa(p_temp, lpf_pb[0..]); var lpf_ps: usize = @intCast(usize, 9) - @intCast(usize, lpf_pl); pal.markerWrite(lpf_pb[lpf_ps..@intCast(usize, 9)]);
                    var lpf_nl2: []const u8 = "\n"; pal.markerWrite(lpf_nl2);
                }
            }
        }
    }
    self.func = func_ptr;
    self.current_bb = createBlock(self);
    emitInst(self, LirInst{ .loop_header = @intCast(u32, 0) });
    self.scope_depth = @intCast(u32, 0);
    self.cur_scope = @intCast(u32, 0);
    self.temp_counter = @intCast(u32, proto.params_count);
    var body = node.child_0;
    if (body != 0) {
        self.block_terminated = @intCast(u8, 0);
        lowerStmtBody(self, body);
    }
    expandDefers(self, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 1));
    if (self.block_terminated == @intCast(u8, 0)) {
        emitValuelessReturn(self);
    }
    hoistTemps(self);
    var hi: usize = 0;
    var ht0: []const u8 = "D3HT:"; pal.markerWrite(ht0);
    while (hi < self.hoisted_temps.len) : (hi += 1) {
        var td = self.hoisted_temps.items[hi];
        dbgPrintU32(td.temp_id);
        var sp: []const u8 = ","; pal.markerWrite(sp);
        dbgPrintU32(td.type_id);
        if (hi + 1 < self.hoisted_temps.len) {
            var sep: []const u8 = "|"; pal.markerWrite(sep);
        }
    }
    var htnl: []const u8 = "\n"; pal.markerWrite(htnl);
    func_ptr.hoisted_temps = self.hoisted_temps;
    return func_ptr.*;
}

pub fn lowerModuleInit(self: *LirLowerer, decls: []const u32, mod_id: u32) LirFunction {
    var store = self.ctx.store;
    var init_s: []const u8 = "__module_init";
    var init_name_id = si_mod.stringInternerIntern(self.ctx.registry.interner, init_s);
    var func_raw = alloc_mod.sandAlloc(self.alloc, @intCast(usize, @sizeOf(LirFunction)), @intCast(usize, 4)) catch unreachable;
    var func_ptr = @ptrCast(*LirFunction, func_raw);
    func_ptr.name_id = init_name_id;
    func_ptr.module_id = mod_id;
    func_ptr.return_type = type_mod.TYPE_VOID;
    func_ptr.params = lir_mod.lirParamArrayListInit(self.alloc);
    func_ptr.blocks = lir_mod.basicBlockArrayListInit(self.alloc);
    func_ptr.hoisted_temps = lir_mod.tempDeclArrayListInit(self.alloc);
    func_ptr.switch_cases = lir_mod.switchCaseArrayListInit(self.alloc);
    func_ptr.side_table = lir_mod.lirSideEntryArrayListInit(self.alloc);
    func_ptr.temp_variant_sub_field = hash_mod.u32ToU32MapInit(self.alloc);
    func_ptr.is_extern = @intCast(u8, 0);
    func_ptr.is_pub = @intCast(u8, 0);
    func_ptr.is_variadic = @intCast(u8, 0);
    self.func = func_ptr;
    self.current_bb = createBlock(self);
    emitInst(self, LirInst{ .loop_header = @intCast(u32, 0) });
    self.scope_depth = @intCast(u32, 0);
    self.cur_scope = @intCast(u32, 0);
    self.temp_counter = @intCast(u32, 0);
    var di: usize = @intCast(usize, 0);
    while (di < decls.len) : (di += @intCast(usize, 1)) {
        var dcl = ast_mod.astStoreNodeAt(store, decls[di]);
        if (dcl.kind != AstKind.var_decl) continue;
        if ((@intCast(u16, dcl.flags) & @intCast(u16, 0x04)) != @intCast(u16, 0)) continue;
        if (dcl.child_1 == @intCast(u32, 0)) continue;
        var g_name_id: u32 = ast_mod.astStoreNodePayload(store, decls[di]);
        var g_sym = sym_mod.symbolRegistryQualifiedLookup(self.ctx.symbol_tables, mod_id, g_name_id);
        if (g_sym) |gss| {
            if (gss.kind != sym_mod.SymbolKind.global) continue;
            var ginit = ast_mod.astStoreNodeAt(store, dcl.child_1);
            if (ginit.kind == AstKind.undefined_literal) continue;
            if (ginit.kind == AstKind.import_expr) continue;
            if (ginit.kind == AstKind.struct_decl or ginit.kind == AstKind.enum_decl or ginit.kind == AstKind.union_decl or ginit.kind == AstKind.error_set_decl) continue;
            if (ginit.kind == AstKind.field_access) {
                var fa_base2 = ast_mod.astStoreNodeAt(store, ginit.child_0);
                if (fa_base2.kind == AstKind.import_expr) continue;
            }
            if ((@intCast(u16, dcl.flags) & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                if (ginit.kind == AstKind.int_literal or ginit.kind == AstKind.float_literal or ginit.kind == AstKind.char_literal) continue;
            }
            var val_t = lowerExpr(self, dcl.child_1);
            emitInst(self, LirInst{ .store_global = .{ .name_id = g_name_id, .module_id = gss.module_id, .value = val_t } });
        }
    }
    emitValuelessReturn(self);
    hoistTemps(self);
    func_ptr.hoisted_temps = self.hoisted_temps;
    return func_ptr.*;
}
