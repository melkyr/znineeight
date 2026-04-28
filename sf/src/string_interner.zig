const hash_mod = @import("util/hash.zig");
const mem_mod = @import("util/mem.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const ga_mod = @import("growable_array.zig");
const U32ArrayList = ga_mod.U32ArrayList;

pub const InternEntry = struct {
    text: []const u8,
    hash: u32,
    next: u32,
};

const InternArrayList = struct {
    items: [*]InternEntry,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

fn internArrayListInit(allocator: *Sand) InternArrayList {
    return InternArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

fn internArrayListEnsureCapacity(self: *InternArrayList, new_capacity: usize) !void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = try alloc_mod.sandAlloc(self.allocator, @intCast(usize, 12) * new_cap, @intCast(usize, 4));
    var new_items = @ptrCast([*]InternEntry, raw);
    var i: usize = 0;
    while (i < self.len) {
        new_items[i] = self.items[i];
        i += 1;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

fn internArrayListAppend(self: *InternArrayList, value: InternEntry) !void {
    try internArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

fn internArrayListGetSlice(self: *InternArrayList) []InternEntry {
    return self.items[0..self.len];
}

pub const StringInterner = struct {
    buckets: *U32ArrayList,
    entries: *InternArrayList,
    allocator: *Sand,
};

pub fn stringInternerInit(allocator: *Sand, bucket_count: u32) !StringInterner {
    var b_raw = try alloc_mod.sandAlloc(allocator, @intCast(usize, 28), @intCast(usize, 4));
    var b_ptr = @ptrCast(*U32ArrayList, b_raw);
    b_ptr.* = ga_mod.u32ArrayListInit(allocator);
    try ga_mod.u32ArrayListEnsureCapacity(b_ptr, bucket_count);
    var i: u32 = 0;
    while (i < bucket_count) {
        try ga_mod.u32ArrayListAppend(b_ptr, 0);
        i += 1;
    }

    var e_raw = try alloc_mod.sandAlloc(allocator, @intCast(usize, 28), @intCast(usize, 4));
    var e_ptr = @ptrCast(*InternArrayList, e_raw);
    e_ptr.* = internArrayListInit(allocator);
    try internArrayListAppend(e_ptr, InternEntry{
        .text = "",
        .hash = @intCast(u32, 0),
        .next = @intCast(u32, 0),
    });

    return StringInterner{
        .buckets = b_ptr,
        .entries = e_ptr,
        .allocator = allocator,
    };
}

pub fn stringInternerIntern(self: *StringInterner, text: []const u8) !u32 {
    var hash = hash_mod.fnv1a(text);
    var bucket_count = self.buckets.len;
    if (bucket_count == 0) {
        try stringInternerGrowBuckets(self, 8);
        bucket_count = self.buckets.len;
    }
    var bucket = hash % @intCast(u32, bucket_count);
    var idx = self.buckets.items[@intCast(usize, bucket)];
    while (idx != 0) {
        var entry = &self.entries.items[@intCast(usize, idx)];
        if (entry.hash == hash and mem_mod.mem_eql(entry.text, text)) return idx;
        idx = entry.next;
    }
    var new_idx = self.entries.len;
    var copied = stringInternerCopyToArena(self, text);
    try internArrayListAppend(self.entries, InternEntry{
        .text = copied[0..text.len],
        .hash = hash,
        .next = self.buckets.items[@intCast(usize, bucket)],
    });
    self.buckets.items[@intCast(usize, bucket)] = @intCast(u32, new_idx);

    var entry_count = self.entries.len;
    if (entry_count * 2 > bucket_count) {
        try stringInternerGrowBuckets(self, @intCast(u32, bucket_count * 2));
    }
    return @intCast(u32, new_idx);
}

pub fn stringInternerGet(self: *StringInterner, id: u32) []const u8 {
    return self.entries.items[@intCast(usize, id)].text;
}

fn stringInternerCopyToArena(self: *StringInterner, text: []const u8) [*]u8 {
    var raw = alloc_mod.sandAlloc(self.allocator, text.len, @intCast(usize, 1)) catch unreachable;
    var i: usize = 0;
    while (i < text.len) {
        raw[i] = text[i];
        i += 1;
    }
    return raw;
}

fn stringInternerGrowBuckets(self: *StringInterner, new_bucket_count: u32) !void {
    self.buckets.len = @intCast(usize, 0);
    try ga_mod.u32ArrayListEnsureCapacity(self.buckets, new_bucket_count);
    var i: u32 = 0;
    while (i < new_bucket_count) {
        try ga_mod.u32ArrayListAppend(self.buckets, 0);
        i += 1;
    }

    var entries_slice = internArrayListGetSlice(self.entries);
    var ei: usize = 1;
    while (ei < self.entries.len) {
        var bucket = entries_slice[ei].hash % new_bucket_count;
        entries_slice[ei].next = self.buckets.items[@intCast(usize, bucket)];
        self.buckets.items[@intCast(usize, bucket)] = @intCast(u32, ei);
        ei += 1;
    }
}
