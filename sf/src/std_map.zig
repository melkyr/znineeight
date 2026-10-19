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
// All three are open-addressed Robin Hood hash tables over a fixed-capacity
// arena allocation made once at init. Slots are the next power of two at or
// above capacity/0.75 (so the load factor never exceeds 0.75); the home slot is
// `hash & mask`. Insertion carries a record and swaps it with any occupant it
// has probed further than, keeping probe distances balanced. `put` on an
// existing key replaces the value in place; a new key when `len == capacity`
// is `error.OutOfMemory` (the caller capacity is the entry limit). `remove`
// uses backward-shift deletion: following entries shift back one slot while
// their probe distance stays positive, so no tombstones are left behind.
//
// Entry `state` is the control byte: `0x80` empty, `0xFE` reserved (deleted,
// never observable in a steady-state table), and `0x00..0x7F` the 7-bit hash
// fragment of a used slot. Probe distance is computed on demand as
// `(slot - home) & mask`; no distance field is stored, so long same-home
// clusters cannot wrap a narrow counter.
//
// Determinism (blueprint §1 R6): the slot a key occupies is a pure function of
// the key, the table capacity, and the insertion/removal sequence — there is no
// address, clock, or PID input. Iteration over the backing table is
// slot-ascending and therefore deterministic.
//
// String keys are copied byte-for-byte into the arena at put, so a stored key
// never aliases the caller's buffer; lookup is by byte content via
// `std_str.eql`. The maps never free: arena reset reclaims everything.

const arena_mod = @import("std_arena.zig");
const str_mod = @import("std_str.zig");
const mem_mod = @import("std_mem.zig");

const STATE_EMPTY: u8 = 0x80;

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
    mask: usize,
};

pub const Map32Ptr = struct {
    entries: [*]Entry32Ptr,
    capacity: usize,
    len: usize,
    mask: usize,
};

pub const MapStrPtr = struct {
    arena: *arena_mod.Arena,
    entries: [*]EntryStrPtr,
    capacity: usize,
    len: usize,
    mask: usize,
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

// Smallest power of two with slots * 3 >= capacity * 4, i.e. the internal
// table never runs above a 0.75 load factor. Capacity 0 has no slots.
fn slotsFor(capacity: usize) usize {
    if (capacity == 0) return 0;
    var n: usize = 1;
    while (n * 3 < capacity * 4) : (n *= 2) {}
    return n;
}

fn fragOf(h: u32) u8 {
    return @intCast(u8, h & 0x7F);
}

fn slotOf(h: u32, mask: usize) usize {
    return @intCast(usize, h) & mask;
}

// On-demand probe distance: no stored distance, so a cluster longer than 255
// entries is represented exactly (a stored u8 would wrap and strand keys).
fn dist32x32(m: *const Map32x32, idx: usize) usize {
    var home: usize = slotOf(mix32(m.entries[idx].key), m.mask);
    return (idx -% home) & m.mask;
}

fn dist32Ptr(m: *const Map32Ptr, idx: usize) usize {
    var home: usize = slotOf(mix32(m.entries[idx].key), m.mask);
    return (idx -% home) & m.mask;
}

fn distStrPtr(m: *const MapStrPtr, idx: usize) usize {
    var home: usize = slotOf(hashBytes(m.entries[idx].key), m.mask);
    return (idx -% home) & m.mask;
}

// ---- Map32x32 --------------------------------------------------------------

pub fn map32x32Init(arena: *arena_mod.Arena, capacity: usize) !Map32x32 {
    var slots: usize = slotsFor(capacity);
    var bytes: usize = slots * @sizeOf(Entry32x32);
    var raw = try arena_mod.alloc(arena, bytes);
    mem_mod.zeroU8(raw, bytes);
    var p: [*]Entry32x32 = @ptrCast([*]Entry32x32, raw);
    var i: usize = 0;
    while (i < slots) : (i += 1) {
        p[i].state = STATE_EMPTY;
    }
    var mask: usize = 0;
    if (slots != 0) mask = slots - 1;
    return Map32x32{ .entries = p, .capacity = capacity, .len = 0, .mask = mask };
}

pub fn map32x32Get(m: *Map32x32, key: u32) ?u32 {
    if (m.capacity == 0) return null;
    var h: u32 = mix32(key);
    var frag: u8 = fragOf(h);
    var idx: usize = slotOf(h, m.mask);
    var slots: usize = m.mask + 1;
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return null;
        if (st == frag and m.entries[idx].key == key) return m.entries[idx].val;
        idx = (idx + 1) & m.mask;
    }
    return null;
}

pub fn map32x32Put(m: *Map32x32, key: u32, val: u32) !void {
    if (m.capacity == 0) return error.OutOfMemory;
    var h: u32 = mix32(key);
    var frag: u8 = fragOf(h);
    var slots: usize = m.mask + 1;

    // Replace an existing key first: it never allocates and never changes len.
    var idx: usize = slotOf(h, m.mask);
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) break;
        if (st == frag and m.entries[idx].key == key) {
            m.entries[idx].val = val;
            return;
        }
        idx = (idx + 1) & m.mask;
    }
    if (m.len == m.capacity) return error.OutOfMemory;

    // Robin Hood: carry the new record, swapping on greater probe distance.
    var cur_key: u32 = key;
    var cur_val: u32 = val;
    var cur_frag: u8 = frag;
    var dist: usize = 0;
    idx = slotOf(h, m.mask);
    step = 0;
    while (step < slots) : (step += 1) {
        var st2: u8 = m.entries[idx].state;
        if (st2 == STATE_EMPTY) {
            m.entries[idx].key = cur_key;
            m.entries[idx].val = cur_val;
            m.entries[idx].state = cur_frag;
            m.len += 1;
            return;
        }
        var od: usize = dist32x32(m, idx);
        if (dist > od) {
            var tk: u32 = m.entries[idx].key;
            var tv: u32 = m.entries[idx].val;
            var tf: u8 = m.entries[idx].state;
            m.entries[idx].key = cur_key;
            m.entries[idx].val = cur_val;
            m.entries[idx].state = cur_frag;
            cur_key = tk;
            cur_val = tv;
            cur_frag = tf;
            dist = od;
        }
        idx = (idx + 1) & m.mask;
        dist += 1;
    }
    return error.OutOfMemory;
}

pub fn map32x32Remove(m: *Map32x32, key: u32) bool {
    if (m.capacity == 0) return false;
    var h: u32 = mix32(key);
    var frag: u8 = fragOf(h);
    var slots: usize = m.mask + 1;
    var idx: usize = slotOf(h, m.mask);
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return false;
        if (st == frag and m.entries[idx].key == key) {
            m.len -= 1;
            var hole: usize = idx;
            var shift: usize = 0;
            while (shift < slots) : (shift += 1) {
                var next: usize = (hole + 1) & m.mask;
                var nst: u8 = m.entries[next].state;
                if (nst == STATE_EMPTY) {
                    m.entries[hole].state = STATE_EMPTY;
                    return true;
                }
                var nd: usize = dist32x32(m, next);
                if (nd == 0) {
                    m.entries[hole].state = STATE_EMPTY;
                    return true;
                }
                m.entries[hole].key = m.entries[next].key;
                m.entries[hole].val = m.entries[next].val;
                m.entries[hole].state = m.entries[next].state;
                hole = next;
            }
            return true;
        }
        idx = (idx + 1) & m.mask;
    }
    return false;
}

pub fn map32x32Len(m: *const Map32x32) usize {
    return m.len;
}

// ---- Map32Ptr --------------------------------------------------------------

pub fn map32PtrInit(arena: *arena_mod.Arena, capacity: usize) !Map32Ptr {
    var slots: usize = slotsFor(capacity);
    var bytes: usize = slots * @sizeOf(Entry32Ptr);
    var raw = try arena_mod.alloc(arena, bytes);
    mem_mod.zeroU8(raw, bytes);
    var p: [*]Entry32Ptr = @ptrCast([*]Entry32Ptr, raw);
    var i: usize = 0;
    while (i < slots) : (i += 1) {
        p[i].state = STATE_EMPTY;
    }
    var mask: usize = 0;
    if (slots != 0) mask = slots - 1;
    return Map32Ptr{ .entries = p, .capacity = capacity, .len = 0, .mask = mask };
}

pub fn map32PtrGet(m: *Map32Ptr, key: u32) ?*void {
    if (m.capacity == 0) return null;
    var h: u32 = mix32(key);
    var frag: u8 = fragOf(h);
    var idx: usize = slotOf(h, m.mask);
    var slots: usize = m.mask + 1;
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return null;
        if (st == frag and m.entries[idx].key == key) return m.entries[idx].val;
        idx = (idx + 1) & m.mask;
    }
    return null;
}

pub fn map32PtrPut(m: *Map32Ptr, key: u32, val: *void) !void {
    if (m.capacity == 0) return error.OutOfMemory;
    var h: u32 = mix32(key);
    var frag: u8 = fragOf(h);
    var slots: usize = m.mask + 1;

    // Replace an existing key first: it never allocates and never changes len.
    var idx: usize = slotOf(h, m.mask);
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) break;
        if (st == frag and m.entries[idx].key == key) {
            m.entries[idx].val = val;
            return;
        }
        idx = (idx + 1) & m.mask;
    }
    if (m.len == m.capacity) return error.OutOfMemory;

    // Robin Hood: carry the new record, swapping on greater probe distance.
    var cur_key: u32 = key;
    var cur_val: *void = val;
    var cur_frag: u8 = frag;
    var dist: usize = 0;
    idx = slotOf(h, m.mask);
    step = 0;
    while (step < slots) : (step += 1) {
        var st2: u8 = m.entries[idx].state;
        if (st2 == STATE_EMPTY) {
            m.entries[idx].key = cur_key;
            m.entries[idx].val = cur_val;
            m.entries[idx].state = cur_frag;
            m.len += 1;
            return;
        }
        var od: usize = dist32Ptr(m, idx);
        if (dist > od) {
            var tk: u32 = m.entries[idx].key;
            var tv: *void = m.entries[idx].val;
            var tf: u8 = m.entries[idx].state;
            m.entries[idx].key = cur_key;
            m.entries[idx].val = cur_val;
            m.entries[idx].state = cur_frag;
            cur_key = tk;
            cur_val = tv;
            cur_frag = tf;
            dist = od;
        }
        idx = (idx + 1) & m.mask;
        dist += 1;
    }
    return error.OutOfMemory;
}

pub fn map32PtrRemove(m: *Map32Ptr, key: u32) bool {
    if (m.capacity == 0) return false;
    var h: u32 = mix32(key);
    var frag: u8 = fragOf(h);
    var slots: usize = m.mask + 1;
    var idx: usize = slotOf(h, m.mask);
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return false;
        if (st == frag and m.entries[idx].key == key) {
            m.len -= 1;
            var hole: usize = idx;
            var shift: usize = 0;
            while (shift < slots) : (shift += 1) {
                var next: usize = (hole + 1) & m.mask;
                var nst: u8 = m.entries[next].state;
                if (nst == STATE_EMPTY) {
                    m.entries[hole].state = STATE_EMPTY;
                    return true;
                }
                var nd: usize = dist32Ptr(m, next);
                if (nd == 0) {
                    m.entries[hole].state = STATE_EMPTY;
                    return true;
                }
                m.entries[hole].key = m.entries[next].key;
                m.entries[hole].val = m.entries[next].val;
                m.entries[hole].state = m.entries[next].state;
                hole = next;
            }
            return true;
        }
        idx = (idx + 1) & m.mask;
    }
    return false;
}

pub fn map32PtrLen(m: *const Map32Ptr) usize {
    return m.len;
}

// ---- MapStrPtr -------------------------------------------------------------

pub fn mapStrPtrInit(arena: *arena_mod.Arena, capacity: usize) !MapStrPtr {
    var slots: usize = slotsFor(capacity);
    var bytes: usize = slots * @sizeOf(EntryStrPtr);
    var raw = try arena_mod.alloc(arena, bytes);
    mem_mod.zeroU8(raw, bytes);
    var p: [*]EntryStrPtr = @ptrCast([*]EntryStrPtr, raw);
    var i: usize = 0;
    while (i < slots) : (i += 1) {
        p[i].state = STATE_EMPTY;
    }
    var mask: usize = 0;
    if (slots != 0) mask = slots - 1;
    return MapStrPtr{ .arena = arena, .entries = p, .capacity = capacity, .len = 0, .mask = mask };
}

pub fn mapStrPtrGet(m: *MapStrPtr, key: []const u8) ?*void {
    if (m.capacity == 0) return null;
    var h: u32 = hashBytes(key);
    var frag: u8 = fragOf(h);
    var idx: usize = slotOf(h, m.mask);
    var slots: usize = m.mask + 1;
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return null;
        if (st == frag and str_mod.eql(m.entries[idx].key, key)) return m.entries[idx].val;
        idx = (idx + 1) & m.mask;
    }
    return null;
}

// Copy `key` into the arena and store the copy. The allocation is attempted
// only after the probe proves the key is new and the caller capacity has room,
// and it happens before any table mutation, so an OutOfMemory leaves the map
// and the arena untouched.
pub fn mapStrPtrPut(m: *MapStrPtr, key: []const u8, val: *void) !void {
    if (m.capacity == 0) return error.OutOfMemory;
    var h: u32 = hashBytes(key);
    var frag: u8 = fragOf(h);
    var slots: usize = m.mask + 1;

    // Replace an existing key first: it never allocates and never changes len.
    var idx: usize = slotOf(h, m.mask);
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) break;
        if (st == frag and str_mod.eql(m.entries[idx].key, key)) {
            m.entries[idx].val = val;
            return;
        }
        idx = (idx + 1) & m.mask;
    }
    if (m.len == m.capacity) return error.OutOfMemory;

    var raw = try arena_mod.alloc(m.arena, key.len);
    mem_mod.copyU8(raw, key.ptr, key.len);
    var cptr: [*]const u8 = @ptrCast([*]const u8, raw);

    // Robin Hood: carry the new record, swapping on greater probe distance.
    var cur_key: []const u8 = cptr[0..key.len];
    var cur_val: *void = val;
    var cur_frag: u8 = frag;
    var dist: usize = 0;
    idx = slotOf(h, m.mask);
    step = 0;
    while (step < slots) : (step += 1) {
        var st2: u8 = m.entries[idx].state;
        if (st2 == STATE_EMPTY) {
            m.entries[idx].key = cur_key;
            m.entries[idx].val = cur_val;
            m.entries[idx].state = cur_frag;
            m.len += 1;
            return;
        }
        var od: usize = distStrPtr(m, idx);
        if (dist > od) {
            var tk: []const u8 = m.entries[idx].key;
            var tv: *void = m.entries[idx].val;
            var tf: u8 = m.entries[idx].state;
            m.entries[idx].key = cur_key;
            m.entries[idx].val = cur_val;
            m.entries[idx].state = cur_frag;
            cur_key = tk;
            cur_val = tv;
            cur_frag = tf;
            dist = od;
        }
        idx = (idx + 1) & m.mask;
        dist += 1;
    }
    return error.OutOfMemory;
}

pub fn mapStrPtrRemove(m: *MapStrPtr, key: []const u8) bool {
    if (m.capacity == 0) return false;
    var h: u32 = hashBytes(key);
    var frag: u8 = fragOf(h);
    var slots: usize = m.mask + 1;
    var idx: usize = slotOf(h, m.mask);
    var step: usize = 0;
    while (step < slots) : (step += 1) {
        var st: u8 = m.entries[idx].state;
        if (st == STATE_EMPTY) return false;
        if (st == frag and str_mod.eql(m.entries[idx].key, key)) {
            m.len -= 1;
            var hole: usize = idx;
            var shift: usize = 0;
            while (shift < slots) : (shift += 1) {
                var next: usize = (hole + 1) & m.mask;
                var nst: u8 = m.entries[next].state;
                if (nst == STATE_EMPTY) {
                    m.entries[hole].state = STATE_EMPTY;
                    return true;
                }
                var nd: usize = distStrPtr(m, next);
                if (nd == 0) {
                    m.entries[hole].state = STATE_EMPTY;
                    return true;
                }
                m.entries[hole].key = m.entries[next].key;
                m.entries[hole].val = m.entries[next].val;
                m.entries[hole].state = m.entries[next].state;
                hole = next;
            }
            return true;
        }
        idx = (idx + 1) & m.mask;
    }
    return false;
}

pub fn mapStrPtrLen(m: *const MapStrPtr) usize {
    return m.len;
}
