const hash_mod = @import("util/hash.zig");
const mem_mod = @import("util/mem.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const InternEntry = struct {
    text: []const u8,
    hash: u32,
    next: u32,
};

pub const StringInterner = struct {
    buckets_items: [*]u32,
    buckets_len: usize,
    buckets_capacity: usize,
    entries_items: [*]InternEntry,
    entries_len: usize,
    entries_capacity: usize,
    entries_allocator: *Sand,
    allocator: *Sand,
};

fn ensureCapacityBuckets(items: *[*]u32, len: *usize, capacity: *usize, arena: *Sand, new_capacity: usize) void {
    if (new_capacity <= capacity.*) return;
    var new_cap = new_capacity;
    if (new_cap < capacity.* * 2) new_cap = capacity.* * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]u32, raw);
    for (items.*[0..len.*]) |item, i| {
        new_items[i] = item;
    }
    items.* = new_items;
    capacity.* = new_cap;
}

fn ensureCapacityEntries(items: *[*]InternEntry, len: *usize, capacity: *usize, arena: *Sand, new_capacity: usize) void {
    if (new_capacity <= capacity.*) return;
    var new_cap = new_capacity;
    if (new_cap < capacity.* * 2) new_cap = capacity.* * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(arena, @intCast(usize, 16) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]InternEntry, raw);
    for (items.*[0..len.*]) |item, i| {
        new_items[i] = item;
    }
    items.* = new_items;
    capacity.* = new_cap;
}

fn appendBucket(items: *[*]u32, len: *usize, capacity: *usize, arena: *Sand, value: u32) void {
    ensureCapacityBuckets(items, len, capacity, arena, len.* + 1);
    items.*[len.*] = value;
    len.* += 1;
}

fn appendEntry(items: *[*]InternEntry, len: *usize, capacity: *usize, arena: *Sand, value: InternEntry) void {
    ensureCapacityEntries(items, len, capacity, arena, len.* + 1);
    items.*[len.*] = value;
    len.* += 1;
}

pub fn stringInternerInit(allocator: *Sand, bucket_count: u32) StringInterner {
    var interner = StringInterner{
        .buckets_items = undefined,
        .buckets_len = @intCast(usize, 0),
        .buckets_capacity = @intCast(usize, 0),
        .entries_items = undefined,
        .entries_len = @intCast(usize, 0),
        .entries_capacity = @intCast(usize, 0),
        .entries_allocator = allocator,
        .allocator = allocator,
    };
    var i: u32 = 0;
    while (i < bucket_count) {
        appendBucket(&interner.buckets_items, &interner.buckets_len, &interner.buckets_capacity, allocator, @intCast(u32, 0));
        i += 1;
    }
    appendEntry(&interner.entries_items, &interner.entries_len, &interner.entries_capacity, allocator, InternEntry{
        .text = "",
        .hash = @intCast(u32, 0),
        .next = @intCast(u32, 0),
    });
    return interner;
}

pub fn stringInternerIntern(self: *StringInterner, text: []const u8) u32 {
    var hash = hash_mod.fnv1a(text);
    var bucket_count = self.buckets_len;
    if (bucket_count == 0) {
        stringInternerGrowBuckets(self, 8);
        bucket_count = self.buckets_len;
    }
    var bucket = hash % @intCast(u32, bucket_count);
    var idx = self.buckets_items[@intCast(usize, bucket)];
    while (idx != 0) {
        var entry = &self.entries_items[@intCast(usize, idx)];
        if (entry.hash == hash and mem_mod.mem_eql(entry.text, text)) return idx;
        idx = entry.next;
    }
    var new_idx = self.entries_len;
    var copied = stringInternerCopyToArena(self, text);
    appendEntry(&self.entries_items, &self.entries_len, &self.entries_capacity, self.entries_allocator, InternEntry{
        .text = copied[0..text.len],
        .hash = hash,
        .next = self.buckets_items[@intCast(usize, bucket)],
    });
    self.buckets_items[@intCast(usize, bucket)] = @intCast(u32, new_idx);

    var entry_count = self.entries_len;
    if (entry_count * 2 > bucket_count) {
        stringInternerGrowBuckets(self, @intCast(u32, bucket_count * 2));
    }
    return @intCast(u32, new_idx);
}

pub fn stringInternerGet(self: *StringInterner, id: u32) []const u8 {
    return self.entries_items[@intCast(usize, id)].text;
}

fn stringInternerCopyToArena(self: *StringInterner, text: []const u8) [*]u8 {
    var raw = alloc_mod.sandAlloc(self.allocator, text.len, @intCast(usize, 1)) catch unreachable;
    for (text) |c, i| {
        raw[i] = c;
    }
    return raw;
}

fn stringInternerGrowBuckets(self: *StringInterner, new_bucket_count: u32) void {
    self.buckets_len = @intCast(usize, 0);
    ensureCapacityBuckets(&self.buckets_items, &self.buckets_len, &self.buckets_capacity, self.allocator, new_bucket_count);
    var i: u32 = 0;
    while (i < new_bucket_count) {
        self.buckets_items[@intCast(usize, i)] = 0;
        i += 1;
    }
    self.buckets_len = @intCast(usize, new_bucket_count);

    var ei: u32 = 1;
    while (ei < @intCast(u32, self.entries_len)) {
        var entry = &self.entries_items[@intCast(usize, ei)];
        var bucket = entry.hash % new_bucket_count;
        entry.next = self.buckets_items[@intCast(usize, bucket)];
        self.buckets_items[@intCast(usize, bucket)] = @intCast(u32, ei);
        ei += 1;
    }
}
