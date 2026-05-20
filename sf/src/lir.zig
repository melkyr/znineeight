pub const TypeId = @import("type_registry.zig").TypeId;
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const SwitchCase = struct {
    value: u64,
    target_bb: u32,
};

pub const LirParam = struct {
    name_id: u32,
    type_id: TypeId,
};

pub const TempDecl = struct {
    temp_id: u32,
    type_id: TypeId,
};

pub const LirInst = union(enum) {
    decl_temp: struct { temp: u32, type_id: TypeId },
    decl_local: struct { name_id: u32, type_id: TypeId, temp: u32 },
    assign: struct { dst: u32, src: u32 },
    assign_field: struct { base: u32, field_id: u32, src: u32 },
    assign_index: struct { base: u32, index: u32, src: u32 },
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
    load_field: struct { base: u32, field_id: u32, result: u32 },
    store_field: struct { base: u32, field_id: u32, value: u32 },
    load_index: struct { base: u32, index: u32, result: u32 },
    load: struct { ptr: u32, result: u32 },
    store: struct { ptr: u32, value: u32 },
    addr_of: struct { operand: u32, result: u32 },
    wrap_optional: struct { value: u32, result: u32, type_id: TypeId },
    unwrap_optional: struct { value: u32, result: u32 },
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
    bool_const: struct { value: u8, result: u32 },
    undefined_const: struct { result: u32, type_id: TypeId },
    load_local: struct { name_id: u32, result: u32 },
    store_local: struct { name_id: u32, value: u32 },
    load_global: struct { name_id: u32, result: u32 },
    store_global: struct { name_id: u32, value: u32 },
    print_str: struct { string_id: u32 },
    print_val: struct { value: u32, type_id: TypeId, fmt: u8 },
    nop: void,
};

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

pub const LirFunction = struct {
    name_id: u32,
    return_type: TypeId,
    params: LirParamArrayList,
    blocks: BasicBlockArrayList,
    hoisted_temps: TempDeclArrayList,
    switch_cases: SwitchCaseArrayList,
    is_extern: u8,
    is_pub: u8,
};
