pub const TypeId = @import("type_registry.zig").TypeId;
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const hash_mod = @import("util/hash.zig");

pub const SwitchCase = struct {
    value: u64,
    target_bb: u32,
};

pub const LirParam = struct {
    name_id: u32,
    type_id: TypeId,
    temp_id: u32,
};

pub const TempDecl = struct {
    temp_id: u32,
    type_id: TypeId,
};

pub const LirInst = union(enum) {
    decl_temp: struct { temp: u32, type_id: TypeId },
    decl_local: struct { name_id: u32, type_id: TypeId, temp: u32 },
    assign: struct { dst: u32, src: u32, name_id: u32 },
    assign_field: struct { base: u32, field_id: u32, src: u32, name_id: u32 },
    assign_index: struct { base: u32, index: u32, src: u32, name_id: u32 },
    jump: u32,
    branch: struct { cond: u32, then_bb: u32, else_bb: u32 },
    switch_br: struct { cond: u32, cases_start: u32, cases_count: u32, else_bb: u32 },
    loop_header: u32,
    ret: u32,
    ret_void: void,
    label: u32,
    binary: struct { op: u8, lhs: u32, rhs: u32, result: u32 },
    unary: struct { op: u8, operand: u32, result: u32 },
    call: struct { callee: u32, args_start: u32, args_count: u32, result: u32 },
    load_field: struct { base: u32, field_id: u32, result: u32, name_id: u32 },
    store_field: struct { base: u32, field_id: u32, value: u32, name_id: u32 },
    load_index: struct { base: u32, index: u32, result: u32, name_id: u32 },
    load: struct { ptr: u32, result: u32 },
    store: struct { ptr: u32, value: u32 },
    addr_of: struct { operand: u32, result: u32 },
    addr_of_field: struct { base: u32, field_id: u32, result: u32 },
    wrap_optional: struct { value: u32, result: u32, type_id: TypeId },
    call_direct: u32, // side-table slot (see LirSideEntry / lirSideAppendCallDirect)
    va_start: struct { va_list_temp: u32, last_param_temp: u32 },
    va_arg: struct { va_list_temp: u32, type_id: u32, result: u32 },
    va_end: struct { va_list_temp: u32 },
    tail_call: u32, // side-table slot (see LirSideEntry / lirSideAppendTailCall)
    func_ref: struct { name_id: u32, module_id: u32, result: u32 },
     unwrap_optional: struct { value: u32, result: u32 },
     unwrap_optional_abi: struct { value: u32, result: u32 },
     check_optional: struct { value: u32, result: u32 },
    wrap_error_ok: struct { value: u32, result: u32, type_id: TypeId },
    wrap_error_err: struct { value: u32, result: u32, type_id: TypeId },
    unwrap_error_payload: struct { value: u32, result: u32 },
    unwrap_error_code: struct { value: u32, result: u32 },
    check_error: struct { value: u32, result: u32 },
    make_slice: struct { ptr: u32, len: u32, result: u32, type_id: TypeId },
    int_cast: struct { value: u32, target: TypeId, result: u32, is_checked: u8 },
    float_cast: struct { value: u32, target: TypeId, result: u32 },
    ptr_cast: struct { value: u32, target: TypeId, result: u32 },
    int_to_float: struct { value: u32, target: TypeId, result: u32 },
    ptr_to_int: struct { value: u32, result: u32 },
    int_to_ptr: struct { value: u32, target: TypeId, result: u32 },
    int_const: struct { value: u64, result: u32 },
    float_const: struct { value: f64, result: u32 },
    string_const: struct { string_id: u32, result: u32 },
     null_const: struct { result: u32 },
     set_optional_null: struct { result: u32, type_id: TypeId },
     bool_const: struct { value: u8, result: u32 },
    undefined_const: struct { result: u32, type_id: TypeId },
    enum_const: struct { value: u64, result: u32, type_id: TypeId, member_name_id: u32 },
    load_local: struct { name_id: u32, result: u32 },
    store_local: struct { name_id: u32, value: u32 },
    load_global: struct { name_id: u32, module_id: u32, result: u32 },
    store_global: struct { name_id: u32, module_id: u32, value: u32 },
    print_str: struct { string_id: u32 },
    print_val: struct { value: u32, type_id: TypeId, fmt: u8 },
    builtin_put_char: struct { value: u32 },
    builtin_stdout_write: struct { ptr: u32, len: u32 },
    builtin_stderr_write: struct { ptr: u32, len: u32 },
    builtin_get_char: struct { result: u32 },
    builtin_exit: struct { value: u32 },
    builtin_sleep_ms: struct { value: u32 },
    builtin_console_clear: void,
    builtin_console_gotoxy: struct { x: u32, y: u32 },
    builtin_console_set_color: struct { fg: u32, bg: u32 },
    builtin_socket_create: struct { port: u32, result: u32 },
    builtin_socket_bind_listen: struct { sock: u32, backlog: u32, result: u32 },
    builtin_socket_accept: struct { sock: u32, result: u32 },
    builtin_socket_connect: struct { sock: u32, port: u32, result: u32 },
    builtin_socket_send: struct { sock: u32, buf: u32, len: u32, result: u32 },
    builtin_socket_recv: struct { sock: u32, buf: u32, len: u32, result: u32 },
    builtin_socket_select: u32, // side-table slot (see LirSideEntry / lirSideAppendSocketSelect)
    builtin_socket_fd_zero: struct { set: u32 },
    builtin_socket_fd_set: struct { fd: u32, set: u32 },
    builtin_socket_fd_isset: struct { fd: u32, set: u32, result: u32 },
    builtin_socket_close: struct { sock: u32 },
    nop: void,
};

pub const CallDirectData = struct {
    name_id: u32,
    module_id: u32,
    args_start: u32,
    args_count: u32,
    result: u32,
    return_type: u32,
    is_extern: u8,
};

pub const TailCallData = struct {
    callee: u32,
    module_id: u32,
    args_start: u32,
    args_count: u32,
    result: u32,
    return_type: u32,
    is_indirect: u8,
    is_extern: u8,
};

pub const SocketSelectData = struct {
    nfds: u32,
    readfds: u32,
    writefds: u32,
    exceptfds: u32,
    timeout_ms: u32,
    result: u32,
};

// Per-fn side table for the 3 wide LirInst variants. LirInst holds the tag
// (ordinals unchanged) plus a u32 slot; the operands live here. Serialized with
// the function by lirStreamWriteFunction and faulted back in on read (I-3
// Concern 2); payloads are scalar ids, so the byte dump is exact.
pub const LirSideEntry = union {
    call_direct: CallDirectData,
    tail_call: TailCallData,
    socket_select: SocketSelectData,
};

pub const LirSideEntryArrayList = struct {
    items: [*]LirSideEntry,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn lirSideEntryArrayListInit(allocator: *Sand) LirSideEntryArrayList {
    return LirSideEntryArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn lirSideEntryArrayListEnsureCapacity(self: *LirSideEntryArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, @sizeOf(LirSideEntry)) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]LirSideEntry, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn lirSideEntryArrayListAppend(self: *LirSideEntryArrayList, value: LirSideEntry) void {
    lirSideEntryArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn lirSideEntryArrayListGetSlice(self: *LirSideEntryArrayList) []LirSideEntry {
    return self.items[0..self.len];
}

pub const LirInstArrayList = struct {
    items: [*]LirInst,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn lirInstArrayListInit(allocator: *Sand) LirInstArrayList {
    return LirInstArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn lirInstArrayListEnsureCapacity(self: *LirInstArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(LirInst) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]LirInst, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn lirInstArrayListAppend(self: *LirInstArrayList, value: LirInst) void {
    lirInstArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn lirInstArrayListGetSlice(self: *LirInstArrayList) []LirInst {
    return self.items[0..self.len];
}

pub const BasicBlock = struct {
    id: u32,
    insts: LirInstArrayList,
    is_terminated: u8,
};

pub const BasicBlockArrayList = struct {
    items: [*]BasicBlock,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn basicBlockArrayListInit(allocator: *Sand) BasicBlockArrayList {
    return BasicBlockArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn basicBlockArrayListEnsureCapacity(self: *BasicBlockArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(BasicBlock) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]BasicBlock, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn basicBlockArrayListAppend(self: *BasicBlockArrayList, value: BasicBlock) void {
    basicBlockArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn basicBlockArrayListGetSlice(self: *BasicBlockArrayList) []BasicBlock {
    return self.items[0..self.len];
}

pub const LirParamArrayList = struct {
    items: [*]LirParam,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn lirParamArrayListInit(allocator: *Sand) LirParamArrayList {
    return LirParamArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn lirParamArrayListEnsureCapacity(self: *LirParamArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(LirParam) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]LirParam, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn lirParamArrayListAppend(self: *LirParamArrayList, value: LirParam) void {
    lirParamArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn lirParamArrayListGetSlice(self: *LirParamArrayList) []LirParam {
    return self.items[0..self.len];
}

pub const TempDeclArrayList = struct {
    items: [*]TempDecl,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn tempDeclArrayListInit(allocator: *Sand) TempDeclArrayList {
    return TempDeclArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn tempDeclArrayListEnsureCapacity(self: *TempDeclArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(TempDecl) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]TempDecl, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn tempDeclArrayListAppend(self: *TempDeclArrayList, value: TempDecl) void {
    tempDeclArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn tempDeclArrayListGetSlice(self: *TempDeclArrayList) []TempDecl {
    return self.items[0..self.len];
}

pub const SwitchCaseArrayList = struct {
    items: [*]SwitchCase,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn switchCaseArrayListInit(allocator: *Sand) SwitchCaseArrayList {
    return SwitchCaseArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn switchCaseArrayListEnsureCapacity(self: *SwitchCaseArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(SwitchCase) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]SwitchCase, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn switchCaseArrayListAppend(self: *SwitchCaseArrayList, value: SwitchCase) void {
    switchCaseArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn switchCaseArrayListGetSlice(self: *SwitchCaseArrayList) []SwitchCase {
    return self.items[0..self.len];
}


pub const LirSlot = struct {
    module_id: u32,
    disk_offset: u32,
    byte_len: u32,
};

pub const LirSlotArrayList = struct {
    items: [*]LirSlot,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn lirSlotArrayListInit(allocator: *Sand) LirSlotArrayList {
    return LirSlotArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn lirSlotArrayListEnsureCapacity(self: *LirSlotArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 4)) new_cap = @intCast(usize, 4);
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, @sizeOf(LirSlot)) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]LirSlot, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.len) : (i += @intCast(usize, 1)) {
        new_items[i] = self.items[i];
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn lirSlotArrayListAppend(self: *LirSlotArrayList, value: LirSlot) void {
    lirSlotArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn lirSlotArrayListGetSlice(self: *LirSlotArrayList) []LirSlot {
    return self.items[0..self.len];
}

pub const LirFunction = struct {
    name_id: u32,
    module_id: u32,
    return_type: TypeId,
    params: LirParamArrayList,
    blocks: BasicBlockArrayList,
    hoisted_temps: TempDeclArrayList,
    switch_cases: SwitchCaseArrayList,
    side_table: LirSideEntryArrayList,
    temp_variant_sub_field: hash_mod.U32ToU32Map,
    is_extern: u8,
    is_pub: u8,
    is_variadic: u8,
};

pub fn lirSideAppendCallDirect(lfn: *LirFunction, d: CallDirectData) u32 {
    var slot = @intCast(u32, lfn.side_table.len);
    lirSideEntryArrayListAppend(&lfn.side_table, LirSideEntry{ .call_direct = d });
    return slot;
}

pub fn lirSideAppendTailCall(lfn: *LirFunction, d: TailCallData) u32 {
    var slot = @intCast(u32, lfn.side_table.len);
    lirSideEntryArrayListAppend(&lfn.side_table, LirSideEntry{ .tail_call = d });
    return slot;
}

pub fn lirSideAppendSocketSelect(lfn: *LirFunction, d: SocketSelectData) u32 {
    var slot = @intCast(u32, lfn.side_table.len);
    lirSideEntryArrayListAppend(&lfn.side_table, LirSideEntry{ .socket_select = d });
    return slot;
}

pub fn lirSideGetCallDirect(lfn: *LirFunction, slot: u32) CallDirectData {
    return lfn.side_table.items[@intCast(usize, slot)].call_direct;
}

pub fn lirSideGetTailCall(lfn: *LirFunction, slot: u32) TailCallData {
    return lfn.side_table.items[@intCast(usize, slot)].tail_call;
}

pub fn lirSideGetSocketSelect(lfn: *LirFunction, slot: u32) SocketSelectData {
    return lfn.side_table.items[@intCast(usize, slot)].socket_select;
}

pub const ModuleGlobalDecl = struct {
    name_id: u32,
    module_id: u32,
    type_id: u32,
    has_runtime_init: u8,
};

pub const GlobalDeclArrayList = struct {
    items: [*]ModuleGlobalDecl,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn globalDeclArrayListInit(allocator: *Sand) GlobalDeclArrayList {
    return GlobalDeclArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn globalDeclArrayListEnsureCapacity(self: *GlobalDeclArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < @intCast(usize, 4)) new_cap = @intCast(usize, 4);
    if (self.capacity > 0) {
        var grown = alloc_mod.sandTryReallocInPlace(self.allocator,
            @ptrCast([*]u8, self.items),
            self.capacity * @sizeOf(ModuleGlobalDecl),
            new_cap * @sizeOf(ModuleGlobalDecl),
            @intCast(usize, 4));
        if (grown != null) {
            self.capacity = new_cap;
            return;
        }
    }
    var raw = alloc_mod.sandAlloc(self.allocator, @sizeOf(ModuleGlobalDecl) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]ModuleGlobalDecl, raw);
    var i: usize = @intCast(usize, 0);
    while (i < self.len) : (i += @intCast(usize, 1)) {
        new_items[i] = self.items[i];
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn globalDeclArrayListAppend(self: *GlobalDeclArrayList, value: ModuleGlobalDecl) void {
    globalDeclArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn globalDeclArrayListGetSlice(self: *GlobalDeclArrayList) []ModuleGlobalDecl {
    return self.items[0..self.len];
}
