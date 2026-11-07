// std_gpa.zig — Z98 std lib L2: single-threaded general-purpose allocator.
//
// Phase 3.1, Tasks 4-5: the TLSF small tier, the page-run medium tier, direct
// large mappings, plus the GPA configuration, ownership, alignment, zero-size,
// resize, stats, optional shuffle, and safe-check contracts. `std.page` owns
// the OS mappings; every 64 KiB small region, every medium chunk, and every
// large mapping is reserved and committed through it.
//
// Small tier (TLSF):
//   - 64 KiB region, 4096-aligned; region header at offset 0, block area after.
//   - region metadata: fl_bitmap: u32, sl_bitmap: [32]u32,
//     free_heads: [192]?*Block (FL 4..15 x 16 SL = 192 heads).
//   - block: 4-byte size/flags header, 4-byte footer, free-list links in the
//     payload; minimum 16 bytes (24 in safe mode, where a 4-byte live/freed
//     magic suffix sits immediately before the footer); 8-byte alignment. The
//     header has no region pointer: ownership is a range walk over the region
//     list.
//   - size mapping is a bounded 32-iteration floor-log2 scan (no @clz); free
//     list insertion is at the class head, or a seeded LCG position when
//     shuffle is enabled.
//
// Medium tier (page runs):
//   - chunk_bytes default 2 MiB, reserved with pageReserve; the chunk header
//     and the per-page metadata array occupy the first committed pages.
//   - every 4 KiB page has metadata: state, run start, run length. Free runs
//     are bucketed by floor-log2 page count (1, 2, 4, 8, ... pages).
//   - allocation takes the smallest fitting run and splits it; free coalesces
//     adjacent free runs in the same chunk. Data pages are committed on
//     allocation; with safe_checks a fully free run is decommitted.
//   - align > 8 routes here: a run start is page-aligned, so it satisfies every
//     allowed align. A small align > 8 request therefore costs a full page run.
//
// Large tier (direct mappings):
//   - sizes above medium_max reserve size + a page for the header, rounded to
//     64 KiB; the header records size/class/magic and the data starts on the
//     next page, so every allowed align <= PAGE_SIZE is satisfied.
//   - ownership is a range walk over the live large-mapping list; free releases
//     the whole mapping and resize reuses it when the new size fits.
//
// Stats: live_allocs is always tracked; per-tier byte counters track requested
// live bytes. Shuffle permutes TLSF class and medium run insertion order with a
// 32-bit LCG seeded from shuffle_seed (non-security, off by default).
//
// Contracts:
//   - gpaAlloc returns uninitialized memory or null; gpaAllocZeroed is the only
//     zeroing entry; gpaFree does not zero.
//   - align must be a power of two in [8, PAGE_SIZE]; anything else is null.
//   - zero size returns null; gpaResize(ptr, 0, a) returns null and leaves the
//     old block valid; all size arithmetic uses u64 intermediate guards.
//   - gpaFree returns false for a pointer outside every region in all modes
//     and touches no metadata. Owned fast-path frees return true with no
//     further validation; a fast-path double free is a caller bug. With
//     safe_checks=true, small magic (and medium page state / large mapping
//     magic) rejects a double free or corrupt header with false, and the
//     requested payload is filled with 0xDD on free.
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
// Safe-mode small blocks reserve 4 extra bytes for a magic suffix immediately
// before the footer; the minimum must still hold the two free-list links, the
// magic, and the footer.
const MIN_BLOCK_SAFE: usize = 24;
const SMALL_MAGIC: u32 = 0xDEADBEEF;
const SMALL_MAGIC_FREED: u32 = 0xFEEDFACE;
const SMALL_LIMIT: usize = 4096;
const MAX_SMALL_BLOCK: usize = 65535;
const NUM_HEADS: usize = 192;
// Small-block header layout (u32):
//   bit 0        FREE
//   bits 1..16   block size in bytes (16 bits, max 65535)
//   bits 17..28  requested live bytes (12 bits, max 4095)
//   bits 29..31  reserved
// The footer is a pure boundary tag: bit 0 FREE, bits 1..16 size, bits 17..31
// zero. Requested bytes therefore never alias the coalescing footer/header
// size fields.
const SIZE_MASK: u32 = 0x0001FFFE;
const FREE_BIT: u32 = 1;
const REQ_MASK: u32 = 0x1FFE0000;

const Block = struct {
    header: u32,
};

const Region = struct {
    next: usize,
    fl_bitmap: u32,
    sl_bitmap: [32]u32,
    free_heads: [192]?*Block,
};

const MAX_RUN_CLASSES: usize = 16;
const NO_PAGE: u32 = 0xFFFFFFFF;
const PAGE_FREE: u32 = 0;
const PAGE_USED: u32 = 1;

// Medium chunks are page-run allocators. The chunk header and the per-page
// metadata array live in the first committed pages; data pages start at
// `data_offset` (always a page boundary) and are committed on allocation.
const PageMeta = struct {
    state: u32,
    run_start: u32,
    run_len: u32,
    next_free: u32,
    prev_free: u32,
    used_bytes: u32,
};

const MediumChunk = struct {
    next: usize,
    chunk_bytes: usize,
    page_count: u32,
    data_offset: u32,
    free_heads: [MAX_RUN_CLASSES]u32,
};

const LARGE_MAGIC: u32 = 0xDEADBEEF;

// A large mapping reserves a full page for this header (so the data pointer is
// page-aligned) plus the requested bytes, rounded up to the reserve granularity.
const LargeMapping = struct {
    next: usize,
    mapping_bytes: usize,
    size: usize,
    size_class: u32,
    magic: u32,
};

pub const GpaStats = struct {
    small_bytes: usize,
    medium_bytes: usize,
    large_bytes: usize,
    live_allocs: usize,
    chunks: usize,
    regions: usize,
};

pub const Gpa = struct {
    page: page_mod.PageAllocator,
    cfg: GpaConfig,
    regions: ?*Region,
    medium: ?*MediumChunk,
    large: ?*LargeMapping,
    live_allocs: usize,
    small_bytes: usize,
    medium_bytes: usize,
    large_bytes: usize,
    shuffle_state: u32,
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
    return Gpa{
        .page = pa,
        .cfg = cfg,
        .regions = null,
        .medium = null,
        .large = null,
        .live_allocs = 0,
        .small_bytes = 0,
        .medium_bytes = 0,
        .large_bytes = 0,
        .shuffle_state = cfg.shuffle_seed,
    };
}

fn validAlign(align: usize) bool {
    if (align < 8 or align > page_mod.PAGE_SIZE) return false;
    return (align & (align - 1)) == 0;
}

fn blockBytes(g: *Gpa, request: usize) ?usize {
    const v: u64 = @intCast(u64, request);
    var hdr: u64 = @intCast(u64, 8);
    var min_block: u64 = @intCast(u64, MIN_BLOCK);
    if (g.cfg.safe_checks) {
        hdr = @intCast(u64, 12);
        min_block = @intCast(u64, MIN_BLOCK_SAFE);
    }
    const seven: u64 = @intCast(u64, 7);
    const limit: u64 = @intCast(u64, 0xFFFFFFFF);
    var sum: u64 = v + hdr;
    if (sum > limit) return null;
    sum = ((sum + seven) / 8) * 8;
    if (sum < min_block) sum = min_block;
    if (sum > limit) return null;
    return @intCast(usize, sum);
}

fn minBlock(g: *Gpa) usize {
    if (g.cfg.safe_checks) return MIN_BLOCK_SAFE;
    return MIN_BLOCK;
}

// The safe-mode small-block magic lives four bytes before the footer.
fn magicAt(g: *Gpa, b: *Block) *u32 {
    _ = g;
    const pb: [*]u8 = @ptrCast([*]u8, b);
    return @ptrCast(*u32, pb + blockSize(b) - 8);
}

fn writeMagic(g: *Gpa, b: *Block, size: usize, magic: u32) void {
    _ = g;
    const pb: [*]u8 = @ptrCast([*]u8, b);
    const mp: *u32 = @ptrCast(*u32, pb + size - 8);
    mp.* = magic;
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
    return @intCast(usize, (b.header & SIZE_MASK) >> 1);
}

fn isFree(b: *Block) bool {
    return (b.header & FREE_BIT) != 0;
}

fn setBlock(b: *Block, size: usize, free: bool) void {
    var v: u32 = @intCast(u32, size);
    v = v << 1;
    if (free) v = v | FREE_BIT;
    b.header = v;
    const pb: [*]u8 = @ptrCast([*]u8, b);
    const fp: *u32 = @ptrCast(*u32, pb + size - 4);
    fp.* = v;
}

// Requested live bytes occupy the top 12 bits of the allocated header; the
// footer stays a pure FREE|size boundary tag for coalescing.
fn blockRequested(b: *Block) usize {
    return @intCast(usize, (b.header & REQ_MASK) >> 17);
}

fn setBlockRequested(b: *Block, requested: usize) void {
    const bits: u32 = (@intCast(u32, requested) & 0xFFF) << 17;
    b.header = (b.header & ~REQ_MASK) | bits;
}

fn shufflePos(g: *Gpa, count: usize) usize {
    const s: u32 = g.shuffle_state *% 1103515245 +% 12345;
    g.shuffle_state = s;
    if (count == 0) return 0;
    const span: u32 = @intCast(u32, count + 1);
    return @intCast(usize, s % span);
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

fn insertFreeAfter(r: *Region, idx: usize, b: *Block, after: *Block) void {
    const n = linkNext(after);
    setLinkNext(after, @ptrToInt(b));
    setLinkPrev(b, @ptrToInt(after));
    setLinkNext(b, n);
    if (n != 0) {
        const nb: *Block = @intToPtr(*Block, n);
        setLinkPrev(nb, @ptrToInt(b));
    }
    const fl = classFl(idx);
    const sl = classSl(idx);
    r.fl_bitmap = r.fl_bitmap | bitMask(fl);
    r.sl_bitmap[fl] = r.sl_bitmap[fl] | bitMask(sl);
}

fn insertFree(g: *Gpa, r: *Region, b: *Block) void {
    const idx = sizeClass(blockSize(b));
    const fl = classFl(idx);
    const sl = classSl(idx);

    if (g.cfg.shuffle) {
        var count: usize = 0;
        var walk = r.free_heads[idx];
        while (walk) |node| {
            count += 1;
            walk = asBlock(linkNext(node));
        }
        const pos = shufflePos(g, count);
        if (pos > 0 and count > 0) {
            var after = r.free_heads[idx];
            var k: usize = 0;
            while (after) |node| {
                if (k + 1 == pos) {
                    insertFreeAfter(r, idx, b, node);
                    return;
                }
                k += 1;
                after = asBlock(linkNext(node));
            }
        }
    }

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

fn allocateFrom(g: *Gpa, r: *Region, b: *Block, need: usize, requested: usize) [*]u8 {
    const sz = blockSize(b);
    const min = minBlock(g);
    if (sz - need >= min) {
        setBlock(b, need, false);
        const pb: [*]u8 = @ptrCast([*]u8, b);
        const rem: *Block = @ptrCast(*Block, pb + need);
        setBlock(rem, sz - need, true);
        if (g.cfg.safe_checks) {
            writeMagic(g, rem, sz - need, SMALL_MAGIC_FREED);
        }
        insertFree(g, r, rem);
    } else {
        setBlock(b, sz, false);
    }
    setBlockRequested(b, requested);
    if (g.cfg.safe_checks) {
        writeMagic(g, b, blockSize(b), SMALL_MAGIC);
    }
    const out: [*]u8 = @ptrCast([*]u8, b);
    return out + 4;
}

fn allocInRegion(g: *Gpa, r: *Region, need: usize, requested: usize) ?[*]u8 {
    var idx: usize = firstClass(r, need);
    while (idx < NUM_HEADS) {
        var cur = r.free_heads[idx];
        while (cur) |b| {
            if (blockSize(b) >= need) {
                removeFreeAt(r, idx, b);
                return allocateFrom(g, r, b, need, requested);
            }
            cur = asBlock(linkNext(b));
        }
        idx = nextClass(r, idx);
    }
    return null;
}

fn freeBlock(g: *Gpa, r: *Region, b0: *Block) void {
    var b: *Block = b0;
    var size: usize = blockSize(b);
    const base: usize = @ptrToInt(r);
    var off: usize = @ptrToInt(b) - base;
    // Mark the caller's block freed before coalescing so a second free of the
    // same pointer is rejected even when this block gets merged into a larger
    // free block away from its original start.
    if (g.cfg.safe_checks) {
        writeMagic(g, b0, size, SMALL_MAGIC_FREED);
    }

    if (off > BLOCK_START) {
        const pb: [*]u8 = @ptrCast([*]u8, b);
        const fp: *u32 = @ptrCast(*u32, pb - 4);
        const pv = fp.*;
        if ((pv & FREE_BIT) != 0) {
            const psz: usize = @intCast(usize, (pv & SIZE_MASK) >> 1);
            const prev: *Block = @ptrCast(*Block, pb - psz);
            removeFreeAt(r, sizeClass(psz), prev);
            b = prev;
            size += psz;
            off = @ptrToInt(b) - base;
        }
    }

    if (off + size + minBlock(g) <= BLOCK_END) {
        const pb: [*]u8 = @ptrCast([*]u8, b);
        const next: *Block = @ptrCast(*Block, pb + size);
        if (isFree(next)) {
            const nsz = blockSize(next);
            removeFreeAt(r, sizeClass(nsz), next);
            size += nsz;
        }
    }

    setBlock(b, size, true);
    if (g.cfg.safe_checks) {
        writeMagic(g, b, size, SMALL_MAGIC_FREED);
    }
    insertFree(g, r, b);
}

fn asMedium(v: usize) ?*MediumChunk {
    if (v == 0) return null;
    return @intToPtr(*MediumChunk, v);
}

fn chunkMeta(c: *MediumChunk) [*]PageMeta {
    const p: [*]u8 = @ptrCast([*]u8, c);
    return @ptrCast([*]PageMeta, p + @intCast(usize, @sizeOf(MediumChunk)));
}

fn chunkData(c: *MediumChunk) [*]u8 {
    const p: [*]u8 = @ptrCast([*]u8, c);
    return p + @intCast(usize, c.data_offset);
}

fn classOfPages(pages0: usize) usize {
    var pages: usize = pages0;
    if (pages == 0) pages = 1;
    var cls: usize = 0;
    while (pages > 1) : (pages = pages >> 1) {
        cls += 1;
    }
    if (cls >= MAX_RUN_CLASSES) cls = MAX_RUN_CLASSES - 1;
    return cls;
}

fn markRun(meta: [*]PageMeta, start: usize, len: usize, state: u32) void {
    var k: usize = 0;
    while (k < len) : (k += 1) {
        const i = start + k;
        meta[i].state = state;
        meta[i].run_start = @intCast(u32, start);
        meta[i].run_len = @intCast(u32, len);
        meta[i].next_free = NO_PAGE;
        meta[i].prev_free = NO_PAGE;
        meta[i].used_bytes = 0;
    }
}

fn mediumInsertAfter(c: *MediumChunk, start: usize, after: usize) void {
    const meta = chunkMeta(c);
    const n = meta[after].next_free;
    meta[start].next_free = n;
    meta[start].prev_free = @intCast(u32, after);
    meta[after].next_free = @intCast(u32, start);
    if (n != NO_PAGE) {
        const ni = @intCast(usize, n);
        meta[ni].prev_free = @intCast(u32, start);
    }
}

fn insertFreeRun(g: *Gpa, c: *MediumChunk, start: usize) void {
    const meta = chunkMeta(c);
    const len = @intCast(usize, meta[start].run_len);
    const cls = classOfPages(len);
    meta[start].state = PAGE_FREE;
    meta[start].used_bytes = 0;

    if (g.cfg.shuffle) {
        var count: usize = 0;
        var walk = c.free_heads[cls];
        while (walk != NO_PAGE) {
            const wi = @intCast(usize, walk);
            count += 1;
            walk = meta[wi].next_free;
        }
        const pos = shufflePos(g, count);
        if (pos > 0 and count > 0) {
            var cur = c.free_heads[cls];
            var k: usize = 0;
            while (cur != NO_PAGE) {
                const ci = @intCast(usize, cur);
                if (k + 1 == pos) {
                    mediumInsertAfter(c, start, ci);
                    return;
                }
                k += 1;
                cur = meta[ci].next_free;
            }
        }
    }

    const head = c.free_heads[cls];
    meta[start].next_free = head;
    meta[start].prev_free = NO_PAGE;
    if (head != NO_PAGE) {
        const h = @intCast(usize, head);
        meta[h].prev_free = @intCast(u32, start);
    }
    c.free_heads[cls] = @intCast(u32, start);
}

fn removeFreeRun(c: *MediumChunk, start: usize) void {
    const meta = chunkMeta(c);
    const len = @intCast(usize, meta[start].run_len);
    const cls = classOfPages(len);
    const p = meta[start].prev_free;
    const n = meta[start].next_free;
    if (p != NO_PAGE) {
        const pi = @intCast(usize, p);
        meta[pi].next_free = n;
    } else {
        c.free_heads[cls] = n;
    }
    if (n != NO_PAGE) {
        const ni = @intCast(usize, n);
        meta[ni].prev_free = p;
    }
    meta[start].next_free = NO_PAGE;
    meta[start].prev_free = NO_PAGE;
}

fn findFit(c: *MediumChunk, need_pages: usize) ?usize {
    const meta = chunkMeta(c);
    var cls = classOfPages(need_pages);
    while (cls < MAX_RUN_CLASSES) : (cls += 1) {
        var best: usize = 0;
        var best_len: usize = 0;
        var have_best: bool = false;
        var cur = c.free_heads[cls];
        while (cur != NO_PAGE) {
            const idx = @intCast(usize, cur);
            const len = @intCast(usize, meta[idx].run_len);
            if (len >= need_pages) {
                if (!have_best or len < best_len) {
                    best = idx;
                    best_len = len;
                    have_best = true;
                }
            }
            cur = meta[idx].next_free;
        }
        if (have_best) return best;
    }
    return null;
}

fn takeRun(g: *Gpa, c: *MediumChunk, start: usize, need_pages: usize, size: usize) ?[*]u8 {
    const meta = chunkMeta(c);
    const len = @intCast(usize, meta[start].run_len);
    const data = chunkData(c);
    const ptr = data + start * page_mod.PAGE_SIZE;
    const commit_bytes = need_pages * page_mod.PAGE_SIZE;
    if (!page_mod.pageCommit(&g.page, ptr, commit_bytes)) return null;
    removeFreeRun(c, start);
    if (len > need_pages) {
        markRun(meta, start, need_pages, PAGE_USED);
        const rem = start + need_pages;
        const rlen = len - need_pages;
        markRun(meta, rem, rlen, PAGE_FREE);
        insertFreeRun(g, c, rem);
    } else {
        markRun(meta, start, len, PAGE_USED);
    }
    meta[start].used_bytes = @intCast(u32, size);
    return ptr;
}

fn newMediumChunk(g: *Gpa) ?*MediumChunk {
    const chunk_bytes = g.cfg.chunk_bytes;
    const raw = page_mod.pageReserve(&g.page, chunk_bytes) orelse return null;
    const hdr_usize: usize = @sizeOf(MediumChunk);
    const meta_usize: usize = @sizeOf(PageMeta);
    const max_pages: u64 = @intCast(u64, chunk_bytes / page_mod.PAGE_SIZE);
    const raw_off: u64 = @intCast(u64, hdr_usize) + max_pages * @intCast(u64, meta_usize);
    const page_u: u64 = @intCast(u64, page_mod.PAGE_SIZE);
    const data_off64: u64 = ((raw_off + page_u - 1) / page_u) * page_u;
    if (data_off64 >= @intCast(u64, chunk_bytes)) {
        page_mod.pageRelease(&g.page, raw, chunk_bytes);
        return null;
    }
    const data_offset: usize = @intCast(usize, data_off64);
    const page_count: usize = (chunk_bytes - data_offset) / page_mod.PAGE_SIZE;
    if (page_count == 0) {
        page_mod.pageRelease(&g.page, raw, chunk_bytes);
        return null;
    }
    if (!page_mod.pageCommit(&g.page, raw, data_offset)) {
        page_mod.pageRelease(&g.page, raw, chunk_bytes);
        return null;
    }
    const c: *MediumChunk = @ptrCast(*MediumChunk, raw);
    c.next = 0;
    c.chunk_bytes = chunk_bytes;
    c.page_count = @intCast(u32, page_count);
    c.data_offset = @intCast(u32, data_offset);
    var i: usize = 0;
    while (i < MAX_RUN_CLASSES) : (i += 1) {
        c.free_heads[i] = NO_PAGE;
    }
    const meta = chunkMeta(c);
    markRun(meta, 0, page_count, PAGE_FREE);
    insertFreeRun(g, c, 0);
    if (g.medium) |old| {
        c.next = @ptrToInt(old);
    }
    g.medium = c;
    return c;
}

fn mediumPageIndex(c: *MediumChunk, ptr: [*]u8) ?usize {
    const base: usize = @ptrToInt(c);
    const data_base: usize = base + @intCast(usize, c.data_offset);
    const a: usize = @ptrToInt(ptr);
    if (a < data_base) return null;
    const off: usize = a - data_base;
    if (off % page_mod.PAGE_SIZE != 0) return null;
    const idx: usize = off / page_mod.PAGE_SIZE;
    if (idx >= @intCast(usize, c.page_count)) return null;
    return idx;
}

fn findMedium(g: *Gpa, ptr: [*]u8) ?*MediumChunk {
    const a: usize = @ptrToInt(ptr);
    var cur = g.medium;
    while (cur) |c| {
        const base: usize = @ptrToInt(c);
        if (a >= base and a < base + c.chunk_bytes) {
            if (mediumPageIndex(c, ptr) != null) return c;
        }
        cur = asMedium(c.next);
    }
    return null;
}

fn freeMedium(g: *Gpa, c: *MediumChunk, ptr: [*]u8) bool {
    const idx = mediumPageIndex(c, ptr) orelse return false;
    const meta = chunkMeta(c);
    const page_count = @intCast(usize, c.page_count);
    var start = @intCast(usize, meta[idx].run_start);
    var len = @intCast(usize, meta[idx].run_len);
    if (start + len > page_count) return false;
    if (g.cfg.safe_checks) {
        // Page metadata is the medium-tier state: a free (or unowned) page
        // means a double free or a stale pointer, and no metadata is touched.
        if (meta[idx].state != PAGE_USED) return false;
        if (idx < start or idx >= start + len) return false;
    }

    const used = @intCast(usize, meta[start].used_bytes);
    if (g.cfg.safe_checks) {
        if (used > len * page_mod.PAGE_SIZE) return false;
        // Fill the freed run's used bytes before decommit discards the pages.
        const data = chunkData(c);
        const run_data = data + start * page_mod.PAGE_SIZE;
        var fi: usize = 0;
        while (fi < used) : (fi += 1) {
            run_data[fi] = 0xDD;
        }
    }
    if (g.medium_bytes >= used) {
        g.medium_bytes -= used;
    } else {
        g.medium_bytes = 0;
    }

    if (start > 0) {
        if (meta[start - 1].state == PAGE_FREE) {
            const pstart = @intCast(usize, meta[start - 1].run_start);
            const plen = @intCast(usize, meta[start - 1].run_len);
            removeFreeRun(c, pstart);
            start = pstart;
            len += plen;
        }
    }
    if (start + len < page_count) {
        if (meta[start + len].state == PAGE_FREE) {
            const nstart = @intCast(usize, meta[start + len].run_start);
            const nlen = @intCast(usize, meta[start + len].run_len);
            removeFreeRun(c, nstart);
            len += nlen;
        }
    }
    markRun(meta, start, len, PAGE_FREE);
    insertFreeRun(g, c, start);
    if (g.cfg.safe_checks) {
        const data = chunkData(c);
        _ = page_mod.pageDecommit(&g.page, data + start * page_mod.PAGE_SIZE, len * page_mod.PAGE_SIZE);
    }
    return true;
}

fn allocMedium(g: *Gpa, size: usize, align: usize) ?[*]u8 {
    _ = align;
    if (size > g.cfg.medium_max) return null;
    const max_pages: usize = g.cfg.medium_max / page_mod.PAGE_SIZE;
    const sz64: u64 = @intCast(u64, size);
    const page_u: u64 = @intCast(u64, page_mod.PAGE_SIZE);
    var need_pages: usize = @intCast(usize, (sz64 + page_u - 1) / page_u);
    if (need_pages == 0) need_pages = 1;
    if (need_pages > max_pages) return null;

    var cur = g.medium;
    while (cur) |c| {
        if (findFit(c, need_pages)) |start| {
            return takeRun(g, c, start, need_pages, size);
        }
        cur = asMedium(c.next);
    }

    const c = newMediumChunk(g) orelse return null;
    const start = findFit(c, need_pages) orelse return null;
    return takeRun(g, c, start, need_pages, size);
}

fn asLarge(v: usize) ?*LargeMapping {
    if (v == 0) return null;
    return @intToPtr(*LargeMapping, v);
}

fn largeMappingBytes(size: usize) ?usize {
    const sz: u64 = @intCast(u64, size);
    const hdr: u64 = @intCast(u64, page_mod.PAGE_SIZE);
    const gran: u64 = @intCast(u64, page_mod.RESERVE_GRANULARITY);
    const limit: u64 = @intCast(u64, 0xFFFFFFFF);
    var total: u64 = sz + hdr;
    if (total > limit) return null;
    total = ((total + gran - 1) / gran) * gran;
    if (total > limit) return null;
    return @intCast(usize, total);
}

fn allocLarge(g: *Gpa, size: usize) ?[*]u8 {
    const total = largeMappingBytes(size) orelse return null;
    const raw = page_mod.pageReserve(&g.page, total) orelse return null;
    if (!page_mod.pageCommit(&g.page, raw, total)) {
        page_mod.pageRelease(&g.page, raw, total);
        return null;
    }
    const m: *LargeMapping = @ptrCast(*LargeMapping, raw);
    m.next = 0;
    if (g.large) |old| {
        m.next = @ptrToInt(old);
    }
    m.mapping_bytes = total;
    m.size = size;
    m.size_class = @intCast(u32, floorLog2(size));
    m.magic = LARGE_MAGIC;
    g.large = m;
    const base: [*]u8 = @ptrCast([*]u8, m);
    return base + page_mod.PAGE_SIZE;
}

fn findLarge(g: *Gpa, ptr: [*]u8) ?*LargeMapping {
    const a: usize = @ptrToInt(ptr);
    var cur = g.large;
    while (cur) |m| {
        const base: usize = @ptrToInt(m);
        if (a >= base and a < base + m.mapping_bytes) {
            if (a == base + page_mod.PAGE_SIZE) return m;
            return null;
        }
        cur = asLarge(m.next);
    }
    return null;
}

fn freeLarge(g: *Gpa, m: *LargeMapping) bool {
    if (g.cfg.safe_checks) {
        // The mapping header magic catches a stale/corrupt large header before
        // any list surgery; the data is filled (then released) on free.
        if (m.magic != LARGE_MAGIC) return false;
        const raw: [*]u8 = @ptrCast([*]u8, m);
        const data = raw + page_mod.PAGE_SIZE;
        var fi: usize = 0;
        while (fi < m.size) : (fi += 1) {
            data[fi] = 0xDD;
        }
    }
    var prev: ?*LargeMapping = null;
    var cur = g.large;
    while (cur) |c| {
        if (c == m) {
            if (prev) |p| {
                p.next = c.next;
            } else {
                g.large = asLarge(c.next);
            }
            break;
        }
        prev = c;
        cur = asLarge(c.next);
    }
    const used = m.size;
    const raw: [*]u8 = @ptrCast([*]u8, m);
    const bytes = m.mapping_bytes;
    page_mod.pageRelease(&g.page, raw, bytes);
    if (g.large_bytes >= used) {
        g.large_bytes -= used;
    } else {
        g.large_bytes = 0;
    }
    return true;
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
    if (off + minBlock(g) > BLOCK_END) return null;
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
    const init_size = BLOCK_END - BLOCK_START;
    setBlock(b, init_size, true);
    if (g.cfg.safe_checks) {
        writeMagic(g, b, init_size, SMALL_MAGIC_FREED);
    }
    insertFree(g, r, b);
    if (g.regions) |old| {
        r.next = @ptrToInt(old);
    }
    g.regions = r;
    return r;
}

// Safe mode releases a small region once it has collapsed to the single free
// block spanning the entire block area. The caller must be done touching the
// region: it is unlinked before pageRelease, so no later scan can visit it.
fn releaseEmptyRegion(g: *Gpa, r: *Region) bool {
    const base: [*]u8 = @ptrCast([*]u8, r);
    const b = blockAt(base, BLOCK_START);
    if (!isFree(b)) return false;
    if (blockSize(b) != BLOCK_END - BLOCK_START) return false;

    var prev: ?*Region = null;
    var cur = g.regions;
    var found = false;
    while (cur) |c| {
        if (c == r) {
            if (prev) |p| {
                p.next = c.next;
            } else {
                g.regions = asRegion(c.next);
            }
            found = true;
            break;
        }
        prev = c;
        cur = asRegion(c.next);
    }
    if (!found) return false;
    page_mod.pageRelease(&g.page, base, REGION_BYTES);
    return true;
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

    var mc = g.medium;
    while (mc) |c| {
        const nxt = asMedium(c.next);
        const raw: [*]u8 = @ptrCast([*]u8, c);
        page_mod.pageRelease(&g.page, raw, c.chunk_bytes);
        mc = nxt;
    }
    g.medium = null;

    var lm = g.large;
    while (lm) |m| {
        const nxt = asLarge(m.next);
        const raw: [*]u8 = @ptrCast([*]u8, m);
        page_mod.pageRelease(&g.page, raw, m.mapping_bytes);
        lm = nxt;
    }
    g.large = null;
    g.live_allocs = 0;
    g.small_bytes = 0;
    g.medium_bytes = 0;
    g.large_bytes = 0;
}

pub fn gpaAlloc(g: *Gpa, size: usize, align: usize) ?[*]u8 {
    if (size == 0) return null;
    if (!validAlign(align)) return null;

    if (size > g.cfg.medium_max) {
        const p = allocLarge(g, size) orelse return null;
        g.live_allocs += 1;
        g.large_bytes += size;
        return p;
    }

    // A page-aligned run start satisfies every allowed align, so align > 8
    // (and every size at or above the small limit) routes to the medium tier.
    if (align > 8 or size >= SMALL_LIMIT) {
        const p = allocMedium(g, size, align) orelse return null;
        g.live_allocs += 1;
        g.medium_bytes += size;
        return p;
    }

    const need = blockBytes(g, size) orelse return null;

    var cur = g.regions;
    while (cur) |r| {
        if (allocInRegion(g, r, need, size)) |p| {
            g.live_allocs += 1;
            g.small_bytes += size;
            return p;
        }
        cur = asRegion(r.next);
    }

    const r = newRegion(g) orelse return null;
    const p = allocInRegion(g, r, need, size) orelse return null;
    g.live_allocs += 1;
    g.small_bytes += size;
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
    if (findMedium(g, ptr)) |c| {
        if (!freeMedium(g, c, ptr)) return false;
        if (g.live_allocs > 0) g.live_allocs -= 1;
        return true;
    }
    if (findLarge(g, ptr)) |m| {
        if (!freeLarge(g, m)) return false;
        if (g.live_allocs > 0) g.live_allocs -= 1;
        return true;
    }
    const r = findRegion(g, ptr) orelse return false;
    const b = blockForPayload(g, ptr) orelse return false;
    if (g.cfg.safe_checks) {
        // Validate the packed size and range before trusting the suffix magic.
        const sz = blockSize(b);
        if (sz % 8 != 0) return false;
        if (sz < MIN_BLOCK_SAFE) return false;
        const base = @ptrToInt(r);
        const baddr = @ptrToInt(b);
        const region_end = base + REGION_BYTES;
        if (baddr < base or baddr >= region_end) return false;
        if (sz > region_end - baddr) return false;
        if (magicAt(g, b).* != SMALL_MAGIC) return false;
    }
    const requested = blockRequested(b);
    if (g.cfg.safe_checks) {
        if (requested > blockSize(b) - 12) return false;
        // Fill the requested payload only; the magic, links, and footer keep
        // their allocator state.
        var fi: usize = 0;
        while (fi < requested) : (fi += 1) {
            ptr[fi] = 0xDD;
        }
    }
    freeBlock(g, r, b);
    if (g.cfg.safe_checks) {
        _ = releaseEmptyRegion(g, r);
    }
    if (g.small_bytes >= requested) {
        g.small_bytes -= requested;
    } else {
        g.small_bytes = 0;
    }
    if (g.live_allocs > 0) g.live_allocs -= 1;
    return true;
}

pub fn gpaResize(g: *Gpa, ptr: [*]u8, new_size: usize, align: usize) ?[*]u8 {
    if (new_size == 0) return null;
    if (!validAlign(align)) return null;

    if (findMedium(g, ptr)) |c| {
        const idx = mediumPageIndex(c, ptr) orelse return null;
        const meta = chunkMeta(c);
        const start = @intCast(usize, meta[idx].run_start);
        const capacity = @intCast(usize, meta[idx].run_len) * page_mod.PAGE_SIZE;
        const old = @intCast(usize, meta[start].used_bytes);
        // Run starts are page-aligned, so a fitting run always satisfies align.
        if (new_size <= capacity) {
            meta[start].used_bytes = @intCast(u32, new_size);
            if (new_size >= old) {
                g.medium_bytes += new_size - old;
            } else {
                g.medium_bytes -= old - new_size;
            }
            return ptr;
        }
        const newp = gpaAlloc(g, new_size, align) orelse return null;
        var copy_len = old;
        if (new_size < copy_len) copy_len = new_size;
        var i: usize = 0;
        while (i < copy_len) : (i += 1) {
            newp[i] = ptr[i];
        }
        _ = gpaFree(g, ptr);
        return newp;
    }

    if (findLarge(g, ptr)) |m| {
        const capacity = m.mapping_bytes - page_mod.PAGE_SIZE;
        const old = m.size;
        // Large data is page-aligned, so a fitting mapping satisfies align.
        if (new_size <= capacity) {
            m.size = new_size;
            m.size_class = @intCast(u32, floorLog2(new_size));
            if (new_size >= old) {
                g.large_bytes += new_size - old;
            } else {
                g.large_bytes -= old - new_size;
            }
            return ptr;
        }
        const newp = gpaAlloc(g, new_size, align) orelse return null;
        var copy_len = old;
        if (new_size < copy_len) copy_len = new_size;
        var i: usize = 0;
        while (i < copy_len) : (i += 1) {
            newp[i] = ptr[i];
        }
        _ = gpaFree(g, ptr);
        return newp;
    }

    const b = blockForPayload(g, ptr) orelse return null;
    const old_size = blockSize(b);
    const old_requested = blockRequested(b);
    if (new_size < SMALL_LIMIT and align == 8) {
        const need = blockBytes(g, new_size) orelse return null;
        if (need <= old_size) {
            setBlockRequested(b, new_size);
            if (new_size >= old_requested) {
                g.small_bytes += new_size - old_requested;
            } else {
                g.small_bytes -= old_requested - new_size;
            }
            return ptr;
        }
    }

    const newp = gpaAlloc(g, new_size, align) orelse return null;
    var copy_len = old_requested;
    if (new_size < copy_len) copy_len = new_size;
    var i: usize = 0;
    while (i < copy_len) : (i += 1) {
        newp[i] = ptr[i];
    }
    _ = gpaFree(g, ptr);
    return newp;
}

pub fn gpaStats(g: *Gpa) GpaStats {
    var s = GpaStats{
        .small_bytes = g.small_bytes,
        .medium_bytes = g.medium_bytes,
        .large_bytes = g.large_bytes,
        .live_allocs = g.live_allocs,
        .chunks = 0,
        .regions = 0,
    };
    var rcur = g.regions;
    while (rcur) |r| {
        s.regions += 1;
        rcur = asRegion(r.next);
    }
    var ccur = g.medium;
    while (ccur) |c| {
        s.chunks += 1;
        ccur = asMedium(c.next);
    }
    return s;
}
