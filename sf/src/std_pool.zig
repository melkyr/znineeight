// std_pool.zig — Z98 std lib L2: caller-buffer-backed fixed-block pool.
//
// Phase 3.1, Task 6: an independent fixed-block allocator over a caller-owned
// byte buffer. It does not import std.page, std.gpa, or any other allocator;
// every block comes from the buffer handed to poolInit and the pool never
// grows. This is the real-time/typed companion to the arena: O(1) alloc/free,
// object-granular reuse, and a bulk reset.
//
// Layout:
//   - poolInit aligns the buffer start up to `align`, rounds block_size up to
//     `align`, carves block_count = usable / rounded blocks, and threads every
//     block onto a singly linked free list.
//   - each free block stores its next link in its first usize bytes (the
//     rounded block is guaranteed to be at least one pointer wide).
//   - poolAlloc pops the head; poolFree pushes a validated block back onto the
//     head; poolReset rebuilds the list and clears the live count.
//
// Contracts:
//   - block_size == 0 returns null; align must be a power of two in
//     [8, 4096] and anything else returns null.
//   - block_size is rounded up to align; a buffer too small to hold one
//     aligned rounded block returns null (no partial pool).
//   - allocation is O(1) from the free-list head; exhaustion returns null.
//   - poolFree validates range and block alignment structurally and returns
//     false for foreign or misaligned pointers (pool validation is always on).
//   - poolLen returns the number of live blocks; no dynamic growth.

pub const Pool = struct {
    base: [*]u8,
    block_size: usize,
    block_count: usize,
    free_head: ?[*]u8,
    used: usize,
};

fn linkAt(block: [*]u8) *usize {
    return @ptrCast(*usize, block);
}

fn nextOf(block: [*]u8) ?[*]u8 {
    const v: usize = linkAt(block).*;
    if (v == 0) return null;
    return @intToPtr([*]u8, v);
}

fn setNext(block: [*]u8, next: ?[*]u8) void {
    const p: *usize = linkAt(block);
    if (next) |n| {
        p.* = @ptrToInt(n);
    } else {
        p.* = 0;
    }
}

fn buildFreeList(base: [*]u8, block_size: usize, block_count: usize) ?[*]u8 {
    var head: ?[*]u8 = null;
    var i: usize = block_count;
    while (i > 0) {
        i -= 1;
        const block: [*]u8 = base + i * block_size;
        setNext(block, head);
        head = block;
    }
    return head;
}

pub fn poolInit(buf: []u8, block_size: usize, align: usize) ?Pool {
    if (block_size == 0) return null;
    if (align < 8 or align > 4096) return null;
    if ((align & (align - 1)) != 0) return null;

    const mask: usize = align - 1;
    const rounded: usize = (block_size + mask) & ~mask;
    // align is at least 8, so rounded already holds a pointer on the 32-bit
    // target; keep the minimum explicit in case the rule ever changes.
    var block: usize = rounded;
    if (block < @sizeOf(usize)) block = @sizeOf(usize);

    const raw: usize = @ptrToInt(buf.ptr);
    const start: usize = (raw + mask) & ~mask;
    const offset: usize = start - raw;
    if (offset >= buf.len) return null;
    const usable: usize = buf.len - offset;
    if (usable < block) return null;
    const count: usize = usable / block;

    const base: [*]u8 = @intToPtr([*]u8, start);
    var p = Pool{
        .base = base,
        .block_size = block,
        .block_count = count,
        .free_head = null,
        .used = 0,
    };
    p.free_head = buildFreeList(base, block, count);
    return p;
}

pub fn poolAlloc(p: *Pool) ?[*]u8 {
    const head: [*]u8 = p.free_head orelse return null;
    p.free_head = nextOf(head);
    p.used += 1;
    return head;
}

pub fn poolFree(p: *Pool, ptr: [*]u8) bool {
    const base: usize = @ptrToInt(p.base);
    const addr: usize = @ptrToInt(ptr);
    if (addr < base) return false;
    const offset: usize = addr - base;
    if (offset >= p.block_size * p.block_count) return false;
    if (offset % p.block_size != 0) return false;
    if (p.used == 0) return false;

    setNext(ptr, p.free_head);
    p.free_head = ptr;
    p.used -= 1;
    return true;
}

pub fn poolReset(p: *Pool) void {
    p.free_head = buildFreeList(p.base, p.block_size, p.block_count);
    p.used = 0;
}

pub fn poolLen(p: *Pool) usize {
    return p.used;
}
