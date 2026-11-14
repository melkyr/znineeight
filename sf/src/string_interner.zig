const hash_mod = @import("util/hash.zig");
const mem_mod = @import("util/mem.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const pal = @import("pal.zig");

pub const InternEntry = struct {
    text: []const u8,
    next: u32,
};

pub const StringInterner = struct {
    buckets_narrow_items: [*]u16,
    buckets_wide_items: [*]u32,
    buckets_is_wide: bool,
    buckets_len: usize,
    buckets_capacity: usize,
    entries_items: [*]InternEntry,
    entries_len: usize,
    entries_capacity: usize,
    entries_allocator: *Sand,
    allocator: *Sand,
};

const NARROW_BUCKET_MAX_BC: usize = 131070;
const MAX_U16_ENTRY_INDEX: usize = 65535;

fn internerBucketsAllocNarrow(self: *StringInterner, count: usize) void {
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 2) * count, @intCast(usize, 2)) catch unreachable;
    self.buckets_narrow_items = @ptrCast([*]u16, raw);
}

fn internerBucketsAllocWide(self: *StringInterner, count: usize) void {
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 4) * count, @intCast(usize, 4)) catch unreachable;
    self.buckets_wide_items = @ptrCast([*]u32, raw);
}

fn internerBucketGet(self: *StringInterner, bucket: usize) u32 {
    if (self.buckets_is_wide) return self.buckets_wide_items[bucket];
    return @intCast(u32, self.buckets_narrow_items[bucket]);
}

fn internerBucketSet(self: *StringInterner, bucket: usize, value: u32) void {
    if (self.buckets_is_wide) {
        self.buckets_wide_items[bucket] = value;
    } else {
        self.buckets_narrow_items[bucket] = @intCast(u16, value);
    }
}

fn internerBucketZero(self: *StringInterner, bucket: usize) void {
    if (self.buckets_is_wide) {
        self.buckets_wide_items[bucket] = @intCast(u32, 0);
    } else {
        self.buckets_narrow_items[bucket] = @intCast(u16, 0);
    }
}

fn ensureCapacityEntries(items: *[*]InternEntry, len: *usize, capacity: *usize, arena: *Sand, new_capacity: usize) void {
    if (new_capacity <= capacity.*) return;
    var new_cap = new_capacity;
    if (new_cap < capacity.* * 2) new_cap = capacity.* * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(arena, @intCast(usize, @sizeOf(InternEntry)) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]InternEntry, raw);
    for (items.*[0..len.*]) |item, i| {
        new_items[i] = item;
    }
    items.* = new_items;
    capacity.* = new_cap;
}

fn appendEntry(items: *[*]InternEntry, len: *usize, capacity: *usize, arena: *Sand, value: InternEntry) void {
    ensureCapacityEntries(items, len, capacity, arena, len.* + 1);
    items.*[len.*] = value;
    len.* += 1;
}

pub fn stringInternerInit(allocator: *Sand, bucket_count: u32) StringInterner {
    var interner = StringInterner{
        .buckets_narrow_items = undefined,
        .buckets_wide_items = undefined,
        .buckets_is_wide = false,
        .buckets_len = @intCast(usize, 0),
        .buckets_capacity = @intCast(usize, 0),
        .entries_items = undefined,
        .entries_len = @intCast(usize, 0),
        .entries_capacity = @intCast(usize, 0),
        .entries_allocator = allocator,
        .allocator = allocator,
    };
    // F-SWEEP #23: pre-size buckets + entries in a single allocation each instead
    // of the 4→8→16… growth chain (which rehashes and leaks each old array in perm).
    // Bucket count only affects lookup distribution, never insertion order, so this
    // is byte-identity-safe. Entries pre-sized to bucket_count/2 (the load-factor
    // 0.5 bound) so the interner lands near its final capacity without growth.
    // Bucket slots store an entry index (0 == empty): 2-byte slots suffice while
    // bucket_count <= NARROW_BUCKET_MAX_BC (entry capacity <= 65,535); a wider
    // bucket_count (or an entries_len that would cross 65,535) uses the u32 path.
    var bc: usize = @intCast(usize, bucket_count);
    if (bc > NARROW_BUCKET_MAX_BC) interner.buckets_is_wide = true;
    if (bc > @intCast(usize, 0)) {
        if (interner.buckets_is_wide) {
            internerBucketsAllocWide(&interner, bc);
        } else {
            internerBucketsAllocNarrow(&interner, bc);
        }
        var bi: usize = 0;
        while (bi < bc) : (bi += @intCast(usize, 1)) {
            internerBucketZero(&interner, bi);
        }
        interner.buckets_capacity = bc;
        interner.buckets_len = bc;
    }
    var ec: usize = bc / @intCast(usize, 2);
    if (ec < @intCast(usize, 8)) ec = @intCast(usize, 8);
    var entries_raw = alloc_mod.sandAlloc(allocator, @intCast(usize, @sizeOf(InternEntry)) * ec, @intCast(usize, 4)) catch unreachable;
    interner.entries_items = @ptrCast([*]InternEntry, entries_raw);
    interner.entries_capacity = ec;
    interner.entries_items[@intCast(usize, 0)] = InternEntry{
        .text = "",
        .next = @intCast(u32, 0),
    };
    interner.entries_len = @intCast(usize, 1);
    return interner;
}

pub fn stringInternerIntern(self: *StringInterner, text: []const u8) u32 {
    var inth_m: []const u8 = "INT:tl"; pal.markerWriteInt(inth_m, @intCast(u32, text.len));
    if (text.len > @intCast(usize, 0)) { var inth2_m: []const u8 = "INT:t0"; pal.markerWriteInt(inth2_m, @intCast(u32, text[0])); }
    var hash = hash_mod.fnv1a(text);
    var bucket_count = self.buckets_len;
    if (bucket_count == 0) {
        stringInternerGrowBuckets(self, 8);
        bucket_count = self.buckets_len;
    }
    var bucket: usize = @intCast(usize, hash % @intCast(u32, bucket_count));
    var idx: u32 = internerBucketGet(self, bucket);
    while (idx != 0) {
        var entry = &self.entries_items[@intCast(usize, idx)];
        if (mem_mod.mem_eql(entry.text, text)) {
            var indp_m: []const u8 = "INT:dup"; pal.markerWriteInt(indp_m, idx);
            return idx;
        }
        idx = entry.next;
    }
    var new_idx = self.entries_len;
    if (!self.buckets_is_wide and new_idx > MAX_U16_ENTRY_INDEX) {
        stringInternerMakeBucketsWide(self);
    }
    var innw_m: []const u8 = "INT:new"; pal.measureMarkerWriteInt(innw_m, @intCast(u32, new_idx));
    var copied = stringInternerCopyToArena(self, text);
    appendEntry(&self.entries_items, &self.entries_len, &self.entries_capacity, self.entries_allocator, InternEntry{
        .text = copied[0..text.len],
        .next = internerBucketGet(self, bucket),
    });
    internerBucketSet(self, bucket, @intCast(u32, new_idx));

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

fn stringInternerMakeBucketsWide(self: *StringInterner) void {
    if (self.buckets_is_wide) return;
    var count = self.buckets_len;
    internerBucketsAllocWide(self, count);
    self.buckets_is_wide = true;
    var wi: usize = 0;
    while (wi < count) : (wi += @intCast(usize, 1)) {
        self.buckets_wide_items[wi] = @intCast(u32, 0);
    }
    var mei: u32 = 1;
    while (mei < @intCast(u32, self.entries_len)) {
        var entry = &self.entries_items[@intCast(usize, mei)];
        var mh = hash_mod.fnv1a(entry.text);
        var mb: usize = @intCast(usize, mh % @intCast(u32, count));
        entry.next = self.buckets_wide_items[mb];
        self.buckets_wide_items[mb] = mei;
        mei += 1;
    }
}

fn stringInternerGrowBuckets(self: *StringInterner, new_bucket_count: u32) void {
    var new_count: usize = @intCast(usize, new_bucket_count);
    if (new_count > self.buckets_capacity) {
        var new_cap: usize = new_count;
        if (new_cap < self.buckets_capacity * @intCast(usize, 2)) new_cap = self.buckets_capacity * @intCast(usize, 2);
        if (new_cap < @intCast(usize, 8)) new_cap = @intCast(usize, 8);
        if (self.buckets_is_wide) {
            internerBucketsAllocWide(self, new_cap);
        } else {
            internerBucketsAllocNarrow(self, new_cap);
        }
        self.buckets_capacity = new_cap;
    }
    self.buckets_len = @intCast(usize, 0);
    var i: usize = 0;
    while (i < new_count) : (i += @intCast(usize, 1)) {
        internerBucketZero(self, i);
    }
    self.buckets_len = new_count;

    var ei: u32 = 1;
    while (ei < @intCast(u32, self.entries_len)) {
        var entry = &self.entries_items[@intCast(usize, ei)];
        var h = hash_mod.fnv1a(entry.text);
        var bucket: usize = @intCast(usize, h % @intCast(u32, new_count));
        entry.next = internerBucketGet(self, bucket);
        internerBucketSet(self, bucket, @intCast(u32, ei));
        ei += 1;
    }
}
