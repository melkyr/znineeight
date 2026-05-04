const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const U32ArrayList = struct {
    items: [*]u32,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn u32ArrayListInit(allocator: *Sand) U32ArrayList {
    return U32ArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn u32ArrayListEnsureCapacity(self: *U32ArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn u32ArrayListAppend(self: *U32ArrayList, value: u32) void {
    u32ArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn u32ArrayListPopOrNull(self: *U32ArrayList) ?u32 {
    if (self.len == 0) return null;
    self.len -= 1;
    return self.items[self.len];
}

pub fn u32ArrayListGetSlice(self: *U32ArrayList) []u32 {
    return self.items[0..self.len];
}

pub const U8ArrayList = struct {
    items: [*]u8,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn byteArrayListInit(allocator: *Sand) U8ArrayList {
    return U8ArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn byteArrayListGrow(self: *U8ArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 1) * new_cap, @intCast(usize, 1)) catch unreachable;
    var new_items = @ptrCast([*]u8, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn byteArrayListAppend(self: *U8ArrayList, value: u8) void {
    byteArrayListGrow(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn byteArrayListGetSlice(self: *U8ArrayList) []u8 {
    return self.items[0..self.len];
}

pub const AstNodeArrayList = struct {
    items: [*]AstNode,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

const AstNode = @import("ast.zig").AstNode;

pub fn astNodeArrayListInit(allocator: *Sand, initial_capacity: usize) AstNodeArrayList {
    var list = AstNodeArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
    astNodeArrayListEnsureCapacity(&list, initial_capacity);
    return list;
}

pub fn astNodeArrayListEnsureCapacity(self: *AstNodeArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 24) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]AstNode, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn astNodeArrayListAppend(self: *AstNodeArrayList, value: AstNode) void {
    astNodeArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn astNodeArrayListGetSlice(self: *AstNodeArrayList) []AstNode {
    return self.items[0..self.len];
}

pub const U64ArrayList = struct {
    items: [*]u64,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn u64ArrayListInit(allocator: *Sand, initial_capacity: usize) U64ArrayList {
    var list = U64ArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
    u64ArrayListEnsureCapacity(&list, initial_capacity);
    return list;
}

pub fn u64ArrayListEnsureCapacity(self: *U64ArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u64, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn u64ArrayListAppend(self: *U64ArrayList, value: u64) void {
    u64ArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn u64ArrayListGetSlice(self: *U64ArrayList) []u64 {
    return self.items[0..self.len];
}

pub const F64ArrayList = struct {
    items: [*]f64,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn f64ArrayListInit(allocator: *Sand, initial_capacity: usize) F64ArrayList {
    var list = F64ArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
    f64ArrayListEnsureCapacity(&list, initial_capacity);
    return list;
}

pub fn f64ArrayListEnsureCapacity(self: *F64ArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 8) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]f64, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn f64ArrayListAppend(self: *F64ArrayList, value: f64) void {
    f64ArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn f64ArrayListGetSlice(self: *F64ArrayList) []f64 {
    return self.items[0..self.len];
}

pub const FnProtoArrayList = struct {
    items: [*]FnProto,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

const FnProto = @import("ast.zig").FnProto;

pub fn fnProtoArrayListInit(allocator: *Sand, initial_capacity: usize) FnProtoArrayList {
    var list = FnProtoArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
    fnProtoArrayListEnsureCapacity(&list, initial_capacity);
    return list;
}

pub fn fnProtoArrayListEnsureCapacity(self: *FnProtoArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 12) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]FnProto, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn fnProtoArrayListAppend(self: *FnProtoArrayList, value: FnProto) void {
    fnProtoArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn fnProtoArrayListGetSlice(self: *FnProtoArrayList) []FnProto {
    return self.items[0..self.len];
}
