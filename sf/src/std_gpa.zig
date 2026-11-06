// std_gpa.zig — Z98 std lib L2: single-threaded general-purpose allocator.
//
// Phase 3.1, Task 2 skeleton: the TLSF small tier plus the GPA configuration,
// ownership, alignment, zero-size, and resize contracts. Medium page runs and
// direct large mappings land in Tasks 3/4; until then align > 8 and size >= 4096
// return null. `std.page` owns the OS mappings; every 64 KiB small region is
// reserved and committed through it.
//
// Small tier (TLSF):
//   - 64 KiB region, 4096-aligned; region header at offset 0, block area after.
//   - region metadata: fl_bitmap: u32, sl_bitmap: [32]u32,
//     free_heads: [192]?*Block (FL 4..15 x 16 SL = 192 heads).
//   - block: 4-byte size/flags header, 4-byte footer, free-list links in the
//     payload; minimum 16 bytes; 8-byte alignment. The header has no region
//     pointer: ownership is a range walk over the region list.
//   - size mapping is a bounded 32-iteration floor-log2 scan (no @clz); free
//     list insertion is at the class head (shuffle lands in Task 4).
//
// Contracts:
//   - gpaAlloc returns uninitialized memory or null; gpaAllocZeroed is the only
//     zeroing entry; gpaFree does not zero.
//   - align must be a power of two in [8, PAGE_SIZE]; anything else is null.
//   - zero size returns null; gpaResize(ptr, 0, a) returns null and leaves the
//     old block valid; all size arithmetic uses u64 intermediate guards.
//   - gpaFree returns false for a pointer outside every region in all modes
//     and touches no metadata. Owned fast-path frees return true with no
//     further validation; a fast-path double free is a caller bug (safe_checks
//     detection lands in Task 5).
//   - gpaInit validates medium_max/chunk_bytes and never allocates.

const page_mod = @import("std_page.zig");

pub const TargetProfile = enum { target32, target64, target128, target256, target512, modern };

pub const GpaConfig = struct {
    page: page_mod.PageConfig,
    target: TargetProfile,
    medium_max: usize,
    chunk_bytes: usize,
    safe_checks: bool,
    shuffle: bool,
    shuffle_seed: u32,
};

const REGION_BYTES: usize = 65536;
// Region header reserve: next + fl_bitmap + sl_bitmap + the 192 optional
// free-head pointers (1536 B; ~1.7 KiB total on the 32-bit target). 2 KiB
// leaves room for safe-check fields and keeps the block start at 4 mod 8.
const HEADER_BYTES: usize = 2048;
// A block is a 4-byte header + payload + 4-byte footer. Starting the block
// area at 4 mod 8 makes the returned payload (header + 4) 8-byte aligned while
// keeping every block size a multiple of 8. The final 4 bytes are unused so
// the last block also ends at 4 mod 8.
const BLOCK_START: usize = HEADER_BYTES + 4;
const BLOCK_END: usize = REGION_BYTES - 4;
const MIN_BLOCK: usize = 16;
const SMALL_LIMIT: usize = 4096;
const MAX_SMALL_BLOCK: usize = 65535;
const NUM_HEADS: usize = 192;
const SIZE_MASK: u32 = 0xFFFFFFF8;
const FREE_BIT: u32 = 1;

const Block = struct {
    header: u32,
};

const Region = struct {
    next: usize,
    fl_bitmap: u32,
    sl_bitmap: [32]u32,
    free_heads: [192]?*Block,
};

pub const Gpa = struct {
    page: page_mod.PageAllocator,
    cfg: GpaConfig,
    regions: ?*Region,
    live_allocs: usize,
};

fn makeConfig(target: TargetProfile, medium_max: usize, chunk_bytes: usize) GpaConfig {
    return GpaConfig{
        .page = page_mod.pageConfigDefault(),
        .target = target,
        .medium_max = medium_max,
        .chunk_bytes = chunk_bytes,
        .safe_checks = false,
        .shuffle = false,
        .shuffle_seed = 0,
    };
}

pub fn gpaConfigDefault() GpaConfig {
    return gpaConfigTarget64();
}

pub fn gpaConfigTarget32() GpaConfig {
    return makeConfig(.target32, 65536, 1048576);
}

pub fn gpaConfigTarget64() GpaConfig {
    return makeConfig(.target64, 65536, 2097152);
}

pub fn gpaConfigTarget128() GpaConfig {
    return makeConfig(.target128, 131072, 4194304);
}

pub fn gpaConfigTarget256() GpaConfig {
    return makeConfig(.target256, 262144, 8388608);
}

pub fn gpaConfigTarget512() GpaConfig {
    return makeConfig(.target512, 262144, 16777216);
}

pub fn gpaConfigTargetModern() GpaConfig {
    return makeConfig(.modern, 1048576, 16777216);
}

pub fn gpaInit(cfg: GpaConfig) page_mod.PageError!Gpa {
    if (cfg.medium_max == 0) return error.InvalidConfig;
    if (cfg.medium_max % page_mod.PAGE_SIZE != 0) return error.InvalidConfig;
    if (cfg.chunk_bytes % page_mod.RESERVE_GRANULARITY != 0) return error.InvalidConfig;
    if (cfg.chunk_bytes <= cfg.medium_max) return error.InvalidConfig;
    const pa = page_mod.pageInit(cfg.page) catch return error.InvalidConfig;
    return Gpa{ .page = pa, .cfg = cfg, .regions = null, .live_allocs = 0 };
}

fn validAlign(align: usize) bool {
    if (align < 8 or align > page_mod.PAGE_SIZE) return false;
    return (align & (align - 1)) == 0;
}

fn blockBytes(request: usize) ?usize {
    const v: u64 = @intCast(u64, request);
    const hdr: u64 = @intCast(u64, 8);
    const seven: u64 = @intCast(u64, 7);
    const min_block: u64 = @intCast(u64, MIN_BLOCK);
    const limit: u64 = @intCast(u64, 0xFFFFFFFF);
    var sum: u64 = v + hdr;
    if (sum > limit) return null;
    sum = ((sum + seven) / 8) * 8;
    if (sum < min_block) sum = min_block;
    if (sum > limit) return null;
    return @intCast(usize, sum);
}

fn floorLog2(v0: usize) usize {
    var v: usize = v0;
    var r: usize = 0;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        if (v > 1) {
            v = v >> 1;
            r += 1;
        }
    }
    return r;
}

fn sizeClass(size0: usize) usize {
    var size: usize = size0;
    if (size > MAX_SMALL_BLOCK) size = MAX_SMALL_BLOCK;
    var fl: usize = floorLog2(size);
    if (fl < 4) fl = 4;
    if (fl > 15) fl = 15;
    const sl: usize = (size >> @intCast(usize, fl - 4)) & 15;
    return (fl - 4) * 16 + sl;
}

fn classFl(idx: usize) usize {
    return idx / 16 + 4;
}

fn classSl(idx: usize) usize {
    return idx % 16;
}

fn bitMask(i: usize) u32 {
    const one: u32 = 1;
    return one << @intCast(u32, i);
}

fn lowestBit(v0: u32) usize {
    var v: u32 = v0;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        if ((v & 1) != 0) return i;
        v = v >> 1;
    }
    return 32;
}

// Bits at positions >= start. Equivalent to `~0u32 << start`, but avoids the
// checked left-shift overflow trap under -fsafe (the high bits leave the word).
fn maskFrom(start: usize) u32 {
    const b = bitMask(start);
    return ~(b - 1);
}

fn classIndex(fl: usize, sl: usize) usize {
    return (fl - 4) * 16 + sl;
}

fn firstClass(r: *Region, need: usize) usize {
    const start = sizeClass(need);
    const fl = classFl(start);
    const sl = classSl(start);
    const m = r.sl_bitmap[fl] & maskFrom(sl);
    if (m != 0) return classIndex(fl, lowestBit(m));
    if (fl < 15) {
        const fm = r.fl_bitmap & maskFrom(fl + 1);
        if (fm == 0) return NUM_HEADS;
        const fl2 = lowestBit(fm);
        const sm = r.sl_bitmap[fl2];
        if (sm == 0) return NUM_HEADS;
        return classIndex(fl2, lowestBit(sm));
    }
    return NUM_HEADS;
}

fn nextClass(r: *Region, idx: usize) usize {
    const fl = classFl(idx);
    const sl = classSl(idx);
    if (sl < 15) {
        const m = r.sl_bitmap[fl] & maskFrom(sl + 1);
        if (m != 0) return classIndex(fl, lowestBit(m));
    }
    if (fl < 15) {
        const fm = r.fl_bitmap & maskFrom(fl + 1);
        if (fm == 0) return NUM_HEADS;
        const fl2 = lowestBit(fm);
        const sm = r.sl_bitmap[fl2];
        if (sm == 0) return NUM_HEADS;
        return classIndex(fl2, lowestBit(sm));
    }
    return NUM_HEADS;
}

fn asBlock(v: usize) ?*Block {
    if (v == 0) return null;
    return @intToPtr(*Block, v);
}

fn asRegion(v: usize) ?*Region {
    if (v == 0) return null;
    return @intToPtr(*Region, v);
}

fn blockAt(base: [*]u8, off: usize) *Block {
    return @ptrCast(*Block, base + off);
}

fn linkPtr(b: *Block, off: usize) *usize {
    const pb: [*]u8 = @ptrCast([*]u8, b);
    return @ptrCast(*usize, pb + off);
}

fn linkNext(b: *Block) usize {
    const p = linkPtr(b, 4);
    return p.*;
}

fn linkPrev(b: *Block) usize {
    const p = linkPtr(b, 8);
    return p.*;
}

fn setLinkNext(b: *Block, v: usize) void {
    const p = linkPtr(b, 4);
    p.* = v;
}

fn setLinkPrev(b: *Block, v: usize) void {
    const p = linkPtr(b, 8);
    p.* = v;
}

fn blockSize(b: *Block) usize {
    return @intCast(usize, b.header & SIZE_MASK);
}

fn isFree(b: *Block) bool {
    return (b.header & FREE_BIT) != 0;
}

fn setBlock(b: *Block, size: usize, free: bool) void {
    var v: u32 = @intCast(u32, size);
    if (free) v = v | FREE_BIT;
    b.header = v;
    const pb: [*]u8 = @ptrCast([*]u8, b);
    const fp: *u32 = @ptrCast(*u32, pb + size - 4);
    fp.* = v;
}

fn removeFreeAt(r: *Region, idx: usize, b: *Block) void {
    const p = linkPrev(b);
    const n = linkNext(b);
    if (p != 0) {
        const pb: *Block = @intToPtr(*Block, p);
        setLinkNext(pb, n);
    } else {
        r.free_heads[idx] = asBlock(n);
    }
    if (n != 0) {
        const nb: *Block = @intToPtr(*Block, n);
        setLinkPrev(nb, p);
    }
    setLinkNext(b, 0);
    setLinkPrev(b, 0);
    if (r.free_heads[idx] == null) {
        const fl = classFl(idx);
        const sl = classSl(idx);
        const sbit = bitMask(sl);
        r.sl_bitmap[fl] = r.sl_bitmap[fl] & ~sbit;
        if (r.sl_bitmap[fl] == 0) {
            const fbit = bitMask(fl);
            r.fl_bitmap = r.fl_bitmap & ~fbit;
        }
    }
}

fn insertFree(r: *Region, b: *Block) void {
    const idx = sizeClass(blockSize(b));
    const fl = classFl(idx);
    const sl = classSl(idx);
    setLinkPrev(b, 0);
    if (r.free_heads[idx]) |old| {
        setLinkNext(b, @ptrToInt(old));
        setLinkPrev(old, @ptrToInt(b));
    } else {
        setLinkNext(b, 0);
    }
    r.free_heads[idx] = b;
    r.fl_bitmap = r.fl_bitmap | bitMask(fl);
    r.sl_bitmap[fl] = r.sl_bitmap[fl] | bitMask(sl);
}

fn allocateFrom(r: *Region, b: *Block, need: usize) [*]u8 {
    const sz = blockSize(b);
    if (sz - need >= MIN_BLOCK) {
        setBlock(b, need, false);
        const pb: [*]u8 = @ptrCast([*]u8, b);
        const rem: *Block = @ptrCast(*Block, pb + need);
        setBlock(rem, sz - need, true);
        insertFree(r, rem);
    } else {
        setBlock(b, sz, false);
    }
    const out: [*]u8 = @ptrCast([*]u8, b);
    return out + 4;
}

fn allocInRegion(r: *Region, need: usize) ?[*]u8 {
    var idx: usize = firstClass(r, need);
    while (idx < NUM_HEADS) {
        var cur = r.free_heads[idx];
        while (cur) |b| {
            if (blockSize(b) >= need) {
                removeFreeAt(r, idx, b);
                return allocateFrom(r, b, need);
            }
            cur = asBlock(linkNext(b));
        }
        idx = nextClass(r, idx);
    }
    return null;
}

fn freeBlock(r: *Region, b0: *Block) void {
    var b: *Block = b0;
    var size: usize = blockSize(b);
    const base: usize = @ptrToInt(r);
    var off: usize = @ptrToInt(b) - base;

    if (off > BLOCK_START) {
        const pb: [*]u8 = @ptrCast([*]u8, b);
        const fp: *u32 = @ptrCast(*u32, pb - 4);
        const pv = fp.*;
        if ((pv & FREE_BIT) != 0) {
            const psz: usize = @intCast(usize, pv & SIZE_MASK);
            const prev: *Block = @ptrCast(*Block, pb - psz);
            removeFreeAt(r, sizeClass(psz), prev);
            b = prev;
            size += psz;
            off = @ptrToInt(b) - base;
        }
    }

    if (off + size + MIN_BLOCK <= BLOCK_END) {
        const pb: [*]u8 = @ptrCast([*]u8, b);
        const next: *Block = @ptrCast(*Block, pb + size);
        if (isFree(next)) {
            const nsz = blockSize(next);
            removeFreeAt(r, sizeClass(nsz), next);
            size += nsz;
        }
    }

    setBlock(b, size, true);
    insertFree(r, b);
}

fn findRegion(g: *Gpa, ptr: [*]u8) ?*Region {
    const a: usize = @ptrToInt(ptr);
    var cur = g.regions;
    while (cur) |r| {
        const base: usize = @ptrToInt(r);
        if (a >= base and a < base + REGION_BYTES) return r;
        cur = asRegion(r.next);
    }
    return null;
}

fn blockForPayload(g: *Gpa, ptr: [*]u8) ?*Block {
    const r = findRegion(g, ptr) orelse return null;
    const base: usize = @ptrToInt(r);
    const a: usize = @ptrToInt(ptr);
    if (a < base + BLOCK_START + 4) return null;
    const off: usize = a - base - 4;
    if (off + MIN_BLOCK > BLOCK_END) return null;
    const raw: [*]u8 = @ptrCast([*]u8, r);
    return blockAt(raw, off);
}

fn newRegion(g: *Gpa) ?*Region {
    const raw = page_mod.pageReserve(&g.page, REGION_BYTES) orelse return null;
    if (!page_mod.pageCommit(&g.page, raw, REGION_BYTES)) {
        page_mod.pageRelease(&g.page, raw, REGION_BYTES);
        return null;
    }
    const r: *Region = @ptrCast(*Region, raw);
    r.next = 0;
    r.fl_bitmap = 0;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        r.sl_bitmap[i] = 0;
    }
    i = 0;
    while (i < NUM_HEADS) : (i += 1) {
        r.free_heads[i] = null;
    }
    const base: [*]u8 = @ptrCast([*]u8, r);
    const b = blockAt(base, BLOCK_START);
    setBlock(b, BLOCK_END - BLOCK_START, true);
    insertFree(r, b);
    if (g.regions) |old| {
        r.next = @ptrToInt(old);
    }
    g.regions = r;
    return r;
}

pub fn gpaDeinit(g: *Gpa) void {
    var cur = g.regions;
    while (cur) |r| {
        const nxt = asRegion(r.next);
        const raw: [*]u8 = @ptrCast([*]u8, r);
        page_mod.pageRelease(&g.page, raw, REGION_BYTES);
        cur = nxt;
    }
    g.regions = null;
    g.live_allocs = 0;
}

pub fn gpaAlloc(g: *Gpa, size: usize, align: usize) ?[*]u8 {
    if (size == 0) return null;
    if (!validAlign(align)) return null;
    if (align > 8) return null;
    if (size >= SMALL_LIMIT) return null;
    const need = blockBytes(size) orelse return null;

    var cur = g.regions;
    while (cur) |r| {
        if (allocInRegion(r, need)) |p| {
            g.live_allocs += 1;
            return p;
        }
        cur = asRegion(r.next);
    }

    const r = newRegion(g) orelse return null;
    const p = allocInRegion(r, need) orelse return null;
    g.live_allocs += 1;
    return p;
}

pub fn gpaAllocZeroed(g: *Gpa, size: usize, align: usize) ?[*]u8 {
    const p = gpaAlloc(g, size, align) orelse return null;
    var i: usize = 0;
    while (i < size) : (i += 1) {
        p[i] = 0;
    }
    return p;
}

pub fn gpaFree(g: *Gpa, ptr: [*]u8) bool {
    const b = blockForPayload(g, ptr) orelse return false;
    const r = findRegion(g, ptr) orelse return false;
    freeBlock(r, b);
    if (g.live_allocs > 0) g.live_allocs -= 1;
    return true;
}

pub fn gpaResize(g: *Gpa, ptr: [*]u8, new_size: usize, align: usize) ?[*]u8 {
    if (new_size == 0) return null;
    if (!validAlign(align)) return null;
    if (align > 8) return null;
    if (new_size >= SMALL_LIMIT) return null;
    const need = blockBytes(new_size) orelse return null;

    const b = blockForPayload(g, ptr) orelse return null;
    const old_size = blockSize(b);
    if (need <= old_size) return ptr;

    const newp = gpaAlloc(g, new_size, align) orelse return null;
    const old_usable = old_size - 8;
    var copy_len = old_usable;
    if (new_size < copy_len) copy_len = new_size;
    var i: usize = 0;
    while (i < copy_len) : (i += 1) {
        newp[i] = ptr[i];
    }
    _ = gpaFree(g, ptr);
    return newp;
}
