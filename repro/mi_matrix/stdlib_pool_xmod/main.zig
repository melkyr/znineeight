// stdlib_pool_xmod — STDLIB std_pool fixed-block pool GREEN fixture.
//
// Contract (Phase 3.1 Layer 3, Task 6): a caller-buffer-backed fixed-block
// pool, independent of std.gpa.
//   poolInit(buf, block_size, align) ?Pool — rounds block_size up to align,
//       rejects block_size==0, an align outside the power-of-two [8, 4096]
//       range, and a buffer smaller than one rounded block;
//   poolAlloc(p) ?[*]u8 — O(1) from the free-list head, null on exhaustion;
//   poolFree(p, ptr) bool — structural range/alignment validation, false for
//       foreign or misaligned pointers;
//   poolReset(p) void — rebuild the free list;
//   poolLen(p) usize — live blocks.
//
// The 4 KiB buffer is manually aligned to 8 so the 32-byte blocks give exactly
// 128 blocks; the harness slice keeps the length at 4096 regardless of the
// global's natural alignment.
//
// GREEN (contract): deterministic byte-exact stdout ending `pool ok\n`
// (RUNRC=0). Each line is `<check> 1`; a failed check prints 0 and the trailer
// is `pool FAIL`.
const std = @import("std");

var g_fail: u32 = 0;

const ZERO: [*]u8 = @ptrCast([*]u8, @intToPtr(*void, 0));

fn ck(what: []const u8, cond: bool) void {
    std.io.write(what);
    if (cond) {
        std.io.write(" 1\n");
    } else {
        std.io.write(" 0\n");
        g_fail += 1;
    }
}

fn mustPool(p: ?std.pool.Pool, what: []const u8) std.pool.Pool {
    if (p) |v| return v;
    @panic(what);
}

fn aligned(p: [*]u8, a: usize) bool {
    return @ptrToInt(p) % a == 0;
}

var g_raw: [4104]u8 = undefined;
var g_foreign: [64]u8 = undefined;
var g_tiny: [31]u8 = undefined;

pub fn main() void {
    const raw_ptr: [*]u8 = g_raw[0..].ptr;
    const addr: usize = @ptrToInt(raw_ptr);
    const mask: usize = 7;
    const aligned_addr: usize = (addr + mask) & ~mask;
    const buf_ptr: [*]u8 = @intToPtr([*]u8, aligned_addr);
    const buf: []u8 = buf_ptr[0..4096];

    // --- init + first fill: 4096 / 32 == 128 blocks ---
    var maybe = std.pool.poolInit(buf, 32, 8);
    var pool = mustPool(maybe, "pool init");
    ck("init", std.pool.poolLen(&pool) == 0);

    var count: usize = 0;
    var first: [*]u8 = ZERO;
    var last: [*]u8 = ZERO;
    while (true) {
        var q = std.pool.poolAlloc(&pool) orelse break;
        if (count == 0) first = q;
        last = q;
        count += 1;
    }
    ck("blocks", count == 128);
    ck("aligned", aligned(first, 8) and aligned(last, 8));
    ck("exhausted", std.pool.poolAlloc(&pool) == null);
    ck("len_full", std.pool.poolLen(&pool) == 128);

    // --- free one, reallocate it from the free-list head ---
    ck("free", std.pool.poolFree(&pool, last));
    ck("len_after_free", std.pool.poolLen(&pool) == 127);
    var again = std.pool.poolAlloc(&pool) orelse ZERO;
    ck("reuse", again == last);
    ck("len_after_reuse", std.pool.poolLen(&pool) == 128);
    ck("exhausted2", std.pool.poolAlloc(&pool) == null);

    // --- reset returns every block; the pool can be filled again ---
    std.pool.poolReset(&pool);
    ck("reset", std.pool.poolLen(&pool) == 0);
    var refill: usize = 0;
    while (true) {
        var q2 = std.pool.poolAlloc(&pool) orelse break;
        if (q2 != ZERO) refill += 1;
    }
    ck("refill", refill == 128);

    // --- foreign and misaligned frees are rejected structurally ---
    const foreign_ptr: [*]u8 = g_foreign[0..].ptr;
    ck("foreign", !std.pool.poolFree(&pool, foreign_ptr));
    ck("misaligned1", !std.pool.poolFree(&pool, buf_ptr + 1));
    ck("misaligned2", !std.pool.poolFree(&pool, buf_ptr + 8));

    // --- poolInit contracts ---
    ck("zero_block", std.pool.poolInit(buf, 0, 8) == null);
    ck("align_zero", std.pool.poolInit(buf, 32, 0) == null);
    ck("align_three", std.pool.poolInit(buf, 32, 3) == null);
    ck("align_big", std.pool.poolInit(buf, 32, 8192) == null);
    const tiny_buf: []u8 = g_tiny[0..];
    ck("too_small", std.pool.poolInit(tiny_buf, 32, 8) == null);

    if (g_fail == 0) {
        std.io.write("pool ok\n");
    } else {
        std.io.write("pool FAIL\n");
    }
}
