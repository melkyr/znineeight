// std_map.zig — Z98 std lib L4: three concrete hash maps (no generics).
//
// Contract (blueprint §3 L4): alloc arena at init | errors OutOfMemory |
// coroutine no. Imports only L0-L2 (`std_arena`, `std_str`, `std_mem`) — never
// a sibling or higher layer.
//
//   Map32x32    u32 -> u32
//   Map32Ptr    u32 -> *void
//   MapStrPtr   []const u8 -> *void   (keys copied into the arena at put)
//
// All three are open-addressed with linear probing over a fixed-capacity table
// allocated once from the caller's arena at init. `put` on an existing key
// replaces the value in place; a new key on a table with no free slot is
// `error.OutOfMemory`. `remove` marks the slot a tombstone so probe chains stay
// intact; the tombstone is reused by a later `put`.
//
// Determinism (blueprint §1 R6): the slot a key occupies is a pure function of
// the key, the table capacity, and the insertion/removal sequence — there is no
// address, clock, or PID input. Iteration order over the backing table is
// therefore deterministic (insertion-index order: slot index ascending).
//
// String keys are copied byte-for-byte into the arena at put, so a stored key
// never aliases the caller's buffer; lookup is by byte content via
// `std_str.eql`. The maps never free: arena reset reclaims everything.

const arena_mod = @import("std_arena.zig");
const str_mod = @import("std_str.zig");
const mem_mod = @import("std_mem.zig");

const STATE_EMPTY: u8 = 0;
const STATE_USED: u8 = 1;
const STATE_TOMB: u8 = 2;

const Entry32x32 = struct {
    key: u32,
    val: u32,
    state: u8,
};

const Entry32Ptr = struct {
    key: u32,
    val: *void,
    state: u8,
};

const EntryStrPtr = struct {
    key: []const u8,
    val: *void,
    state: u8,
};

pub const Map32x32 = struct {
    entries: [*]Entry32x32,
    capacity: usize,
    len: usize,
};

pub const Map32Ptr = struct {
    entries: [*]Entry32Ptr,
    capacity: usize,
    len: usize,
};

pub const MapStrPtr = struct {
    arena: *arena_mod.Arena,
    entries: [*]EntryStrPtr,
    capacity: usize,
    len: usize,
};

// ---- hashing (deterministic; no address/clock input) ----------------------

// Integer finalizer (the "lowbias32" mix). Every step is a u32 operation with
// the explicit wrap operator, so it is total and -fsafe-clean.
fn mix32(x0: u32) u32 {
    var x: u32 = x0;
    x = x ^ (x >> 16);
    x = x *% 0x7feb352d;
    x = x ^ (x >> 15);
    x = x *% 0x846ca68b;
    x = x ^ (x >> 16);
    return x;
}

// FNV-1a over the key bytes. Empty keys hash to the offset basis.
fn hashBytes(s: []const u8) u32 {
    var h: u32 = 2166136261;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        h = h ^ @intCast(u32, s[i]);
        h = h *% 16777619;
    }
    return h;
}

fn slotOf(h: u32, capacity: usize) usize {
    return @intCast(usize, h) % capacity;
}

// ---- Map32x32 --------------------------------------------------------------

pub fn map32x32Init(arena: *arena_mod.Arena, capacity: usize) !Map32x32 {
    var bytes: usize = capacity * @sizeOf(Entry32x32);
    var raw = try arena_mod.alloc(arena, bytes);
    mem_mod.zeroU8(raw, bytes);
    var p: [*]Entry32x32 = @ptrCast([*]Entry32x32, raw);
    return Map32x32{ .entries = p, .capacity = capacity, .len = 0 };
}

pub fn map32x32Get(m: *Map32x32, key: u32) ?u32 {
    if (m.capacity == 0) return null;
    var idx: usize = slotOf(mix32(key), m.capacity);
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return null;
        if (st == STATE_USED and m.entries[idx].key == key) return m.entries[idx].val;
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    return null;
}

pub fn map32x32Put(m: *Map32x32, key: u32, val: u32) !void {
    if (m.capacity == 0) return error.OutOfMemory;
    var idx: usize = slotOf(mix32(key), m.capacity);
    var first_tomb: usize = m.capacity;
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) {
            var target: usize = idx;
            if (first_tomb != m.capacity) target = first_tomb;
            m.entries[target].key = key;
            m.entries[target].val = val;
            m.entries[target].state = STATE_USED;
            m.len += 1;
            return;
        }
        if (st == STATE_USED and m.entries[idx].key == key) {
            m.entries[idx].val = val;
            return;
        }
        if (st == STATE_TOMB and first_tomb == m.capacity) {
            first_tomb = idx;
        }
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    if (first_tomb != m.capacity) {
        m.entries[first_tomb].key = key;
        m.entries[first_tomb].val = val;
        m.entries[first_tomb].state = STATE_USED;
        m.len += 1;
        return;
    }
    return error.OutOfMemory;
}

pub fn map32x32Remove(m: *Map32x32, key: u32) bool {
    if (m.capacity == 0) return false;
    var idx: usize = slotOf(mix32(key), m.capacity);
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return false;
        if (st == STATE_USED and m.entries[idx].key == key) {
            m.entries[idx].state = STATE_TOMB;
            m.len -= 1;
            return true;
        }
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    return false;
}

pub fn map32x32Len(m: *const Map32x32) usize {
    return m.len;
}

// ---- Map32Ptr --------------------------------------------------------------

pub fn map32PtrInit(arena: *arena_mod.Arena, capacity: usize) !Map32Ptr {
    var bytes: usize = capacity * @sizeOf(Entry32Ptr);
    var raw = try arena_mod.alloc(arena, bytes);
    mem_mod.zeroU8(raw, bytes);
    var p: [*]Entry32Ptr = @ptrCast([*]Entry32Ptr, raw);
    return Map32Ptr{ .entries = p, .capacity = capacity, .len = 0 };
}

pub fn map32PtrGet(m: *Map32Ptr, key: u32) ?*void {
    if (m.capacity == 0) return null;
    var idx: usize = slotOf(mix32(key), m.capacity);
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return null;
        if (st == STATE_USED and m.entries[idx].key == key) return m.entries[idx].val;
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    return null;
}

pub fn map32PtrPut(m: *Map32Ptr, key: u32, val: *void) !void {
    if (m.capacity == 0) return error.OutOfMemory;
    var idx: usize = slotOf(mix32(key), m.capacity);
    var first_tomb: usize = m.capacity;
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) {
            var target: usize = idx;
            if (first_tomb != m.capacity) target = first_tomb;
            m.entries[target].key = key;
            m.entries[target].val = val;
            m.entries[target].state = STATE_USED;
            m.len += 1;
            return;
        }
        if (st == STATE_USED and m.entries[idx].key == key) {
            m.entries[idx].val = val;
            return;
        }
        if (st == STATE_TOMB and first_tomb == m.capacity) {
            first_tomb = idx;
        }
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    if (first_tomb != m.capacity) {
        m.entries[first_tomb].key = key;
        m.entries[first_tomb].val = val;
        m.entries[first_tomb].state = STATE_USED;
        m.len += 1;
        return;
    }
    return error.OutOfMemory;
}

pub fn map32PtrRemove(m: *Map32Ptr, key: u32) bool {
    if (m.capacity == 0) return false;
    var idx: usize = slotOf(mix32(key), m.capacity);
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return false;
        if (st == STATE_USED and m.entries[idx].key == key) {
            m.entries[idx].state = STATE_TOMB;
            m.len -= 1;
            return true;
        }
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    return false;
}

pub fn map32PtrLen(m: *const Map32Ptr) usize {
    return m.len;
}

// ---- MapStrPtr -------------------------------------------------------------

pub fn mapStrPtrInit(arena: *arena_mod.Arena, capacity: usize) !MapStrPtr {
    var bytes: usize = capacity * @sizeOf(EntryStrPtr);
    var raw = try arena_mod.alloc(arena, bytes);
    mem_mod.zeroU8(raw, bytes);
    var p: [*]EntryStrPtr = @ptrCast([*]EntryStrPtr, raw);
    return MapStrPtr{ .arena = arena, .entries = p, .capacity = capacity, .len = 0 };
}

pub fn mapStrPtrGet(m: *MapStrPtr, key: []const u8) ?*void {
    if (m.capacity == 0) return null;
    var idx: usize = slotOf(hashBytes(key), m.capacity);
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return null;
        if (st == STATE_USED and str_mod.eql(m.entries[idx].key, key)) return m.entries[idx].val;
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    return null;
}

// Copy `key` into the arena and store the copy. The allocation is attempted
// only after the probe proves the key is new, and it happens before any table
// mutation, so an OutOfMemory leaves the map and the arena untouched.
pub fn mapStrPtrPut(m: *MapStrPtr, key: []const u8, val: *void) !void {
    if (m.capacity == 0) return error.OutOfMemory;
    var idx: usize = slotOf(hashBytes(key), m.capacity);
    var first_tomb: usize = m.capacity;
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) {
            var target: usize = idx;
            if (first_tomb != m.capacity) target = first_tomb;
            var raw = try arena_mod.alloc(m.arena, key.len);
            mem_mod.copyU8(raw, key.ptr, key.len);
            var cptr: [*]const u8 = @ptrCast([*]const u8, raw);
            m.entries[target].key = cptr[0..key.len];
            m.entries[target].val = val;
            m.entries[target].state = STATE_USED;
            m.len += 1;
            return;
        }
        if (st == STATE_USED and str_mod.eql(m.entries[idx].key, key)) {
            m.entries[idx].val = val;
            return;
        }
        if (st == STATE_TOMB and first_tomb == m.capacity) {
            first_tomb = idx;
        }
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    if (first_tomb != m.capacity) {
        var raw2 = try arena_mod.alloc(m.arena, key.len);
        mem_mod.copyU8(raw2, key.ptr, key.len);
        var cptr2: [*]const u8 = @ptrCast([*]const u8, raw2);
        m.entries[first_tomb].key = cptr2[0..key.len];
        m.entries[first_tomb].val = val;
        m.entries[first_tomb].state = STATE_USED;
        m.len += 1;
        return;
    }
    return error.OutOfMemory;
}

pub fn mapStrPtrRemove(m: *MapStrPtr, key: []const u8) bool {
    if (m.capacity == 0) return false;
    var idx: usize = slotOf(hashBytes(key), m.capacity);
    var step: usize = 0;
    while (step < m.capacity) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return false;
        if (st == STATE_USED and str_mod.eql(m.entries[idx].key, key)) {
            m.entries[idx].state = STATE_TOMB;
            m.len -= 1;
            return true;
        }
        idx += 1;
        if (idx == m.capacity) idx = 0;
    }
    return false;
}

pub fn mapStrPtrLen(m: *const MapStrPtr) usize {
    return m.len;
}
