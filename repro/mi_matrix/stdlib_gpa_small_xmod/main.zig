// stdlib_gpa_small_xmod — STDLIB std_gpa TLSF small-tier GREEN fixture.
//
// Contract (Phase 3.1 Layer 2, Task 2): 64 KiB TLSF regions, block sizes below
// 4096, 8-byte alignment, best-fit/split/coalesce free lists, mixed-order free
// and reuse, range-walk ownership for gpaFree, and the pinned zero/alignment
// rejection contracts. The 4096 boundary now routes to the medium tier and
// returns a page-aligned pointer; this fixture otherwise exercises the small tier.
//
// GREEN (contract): deterministic byte-exact stdout ending `gpa small ok\n`
// (RUNRC=0). Each line is `<check> 1` on success; a failed check prints 0 and
// the trailer is `gpa small FAIL`.
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

fn must(p: ?[*]u8, what: []const u8) [*]u8 {
    if (p) |q| return q;
    @panic(what);
}

fn pageAlignedOpt(p: ?[*]u8) bool {
    if (p) |q| return @ptrToInt(q) % 4096 == 0;
    return false;
}

fn overlaps(a: [*]u8, alen: usize, b: [*]u8, blen: usize) bool {
    const a0: usize = @ptrToInt(a);
    const b0: usize = @ptrToInt(b);
    const a1: usize = a0 + alen;
    const b1: usize = b0 + blen;
    return a0 < b1 and b0 < a1;
}

pub fn main() void {
    const gpa = std.gpa;

    var cfg = gpa.gpaConfigTarget64();
    var g = gpa.gpaInit(cfg) catch {
        std.io.write("gpa small FAIL\n");
        return;
    };
    ck("init", true);

    // --- sizes 1..4095, initial high-byte writes, alignment ---
    const p1 = must(gpa.gpaAlloc(&g, 1, 8), "alloc 1");
    const p8 = must(gpa.gpaAlloc(&g, 8, 8), "alloc 8");
    const p16 = must(gpa.gpaAlloc(&g, 16, 8), "alloc 16");
    const p100 = must(gpa.gpaAlloc(&g, 100, 8), "alloc 100");
    const p1000 = must(gpa.gpaAlloc(&g, 1000, 8), "alloc 1000");
    const p4000 = must(gpa.gpaAlloc(&g, 4000, 8), "alloc 4000");
    const p4095 = must(gpa.gpaAlloc(&g, 4095, 8), "alloc 4095");
    ck("alloc", p1 != ZERO and p8 != ZERO and p16 != ZERO and
        p100 != ZERO and p1000 != ZERO and p4000 != ZERO and p4095 != ZERO);

    p1[0] = 0xA1;
    p8[0] = 0xA8;
    p8[7] = 0x18;
    p16[0] = 0xA6;
    p16[15] = 0x16;
    p100[0] = 0xA0;
    p100[99] = 0x99;
    p1000[0] = 0xA2;
    p1000[999] = 0xE9;
    p4000[0] = 0xA3;
    p4000[3999] = 0x39;
    p4095[0] = 0xA4;
    p4095[4094] = 0x4E;
    ck("bytes", p1[0] == 0xA1 and p8[0] == 0xA8 and p8[7] == 0x18 and
        p16[0] == 0xA6 and p16[15] == 0x16 and
        p100[0] == 0xA0 and p100[99] == 0x99 and
        p1000[0] == 0xA2 and p1000[999] == 0xE9 and
        p4000[0] == 0xA3 and p4000[3999] == 0x39 and
        p4095[0] == 0xA4 and p4095[4094] == 0x4E);

    ck("align", @ptrToInt(p1) % 8 == 0 and @ptrToInt(p8) % 8 == 0 and
        @ptrToInt(p16) % 8 == 0 and @ptrToInt(p100) % 8 == 0 and
        @ptrToInt(p1000) % 8 == 0 and @ptrToInt(p4000) % 8 == 0 and
        @ptrToInt(p4095) % 8 == 0);

    // --- alignment, zero-size rejection, and 4096 medium-boundary success ---
    ck("reject", gpa.gpaAlloc(&g, 16, 0) == null and
        gpa.gpaAlloc(&g, 16, 3) == null and
        gpa.gpaAlloc(&g, 16, 7) == null and
        gpa.gpaAlloc(&g, 16, 8192) == null and
        gpa.gpaAlloc(&g, 0, 8) == null and
        gpa.gpaAllocZeroed(&g, 0, 8) == null and
        pageAlignedOpt(gpa.gpaAlloc(&g, 4096, 8)));

    // --- zeroed allocation is zero-filled ---
    const z = must(gpa.gpaAllocZeroed(&g, 64, 8), "allocZeroed 64");
    var z_ok: bool = @ptrToInt(z) % 8 == 0;
    var zi: usize = 0;
    while (zi < 64) : (zi += 1) {
        if (z[zi] != 0) z_ok = false;
    }
    ck("zero", z_ok);

    // --- resize upward keeps the original bytes ---
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        p1000[i] = @intCast(u8, i & 0xFF);
    }
    const r = must(gpa.gpaResize(&g, p1000, 2000, 8), "resize up");
    var r_ok: bool = @ptrToInt(r) % 8 == 0;
    i = 0;
    while (i < 1000) : (i += 1) {
        if (r[i] != @intCast(u8, i & 0xFF)) r_ok = false;
    }
    ck("resize", r_ok);

    // --- resize to zero returns null and leaves the old block valid ---
    const rz = gpa.gpaResize(&g, r, 0, 8);
    r[0] = 0x5A;
    ck("resize0", rz == null and r[0] == 0x5A);

    // --- bitmap class selection: free 16/100/4000, allocate again ---
    var flow_ok: bool = true;
    if (!gpa.gpaFree(&g, p16)) flow_ok = false;
    if (!gpa.gpaFree(&g, p100)) flow_ok = false;
    if (!gpa.gpaFree(&g, p4000)) flow_ok = false;

    const b16 = gpa.gpaAlloc(&g, 16, 8);
    const b100 = gpa.gpaAlloc(&g, 100, 8);
    const b4000 = gpa.gpaAlloc(&g, 4000, 8);
    if (b16) |bp| {
        if (@ptrToInt(bp) % 8 != 0) flow_ok = false;
        bp[0] = 0x61;
    } else {
        flow_ok = false;
    }
    if (b100) |bp| {
        if (@ptrToInt(bp) % 8 != 0) flow_ok = false;
        bp[0] = 0x64;
    } else {
        flow_ok = false;
    }
    if (b4000) |bp| {
        if (@ptrToInt(bp) % 8 != 0) flow_ok = false;
        bp[0] = 0xFA;
        bp[3999] = 0xAF;
    } else {
        flow_ok = false;
    }

    // --- split the upper-class region tail, mixed frees, reallocate ---
    var tail: [32]?[*]u8 = undefined;
    var ti: usize = 0;
    while (ti < 32) : (ti += 1) {
        tail[ti] = gpa.gpaAlloc(&g, 1200, 8);
        const tp = tail[ti];
        if (tp) |p| {
            if (@ptrToInt(p) % 8 != 0) flow_ok = false;
            p[0] = 0x7A;
            p[1199] = 0x7A;
        } else {
            flow_ok = false;
        }
    }

    ti = 0;
    while (ti < 32) : (ti += 2) {
        const tp = tail[ti];
        if (tp) |p| {
            if (!gpa.gpaFree(&g, p)) flow_ok = false;
            tail[ti] = null;
        }
    }
    var tj: usize = 32;
    while (tj > 0) {
        tj -= 1;
        if (tj % 2 == 1) {
            const tp = tail[tj];
            if (tp) |p| {
                if (!gpa.gpaFree(&g, p)) flow_ok = false;
                tail[tj] = null;
            }
        }
    }

    ti = 0;
    while (ti < 32) : (ti += 2) {
        tail[ti] = gpa.gpaAlloc(&g, 1200, 8);
        const tp = tail[ti];
        if (tp) |p| {
            if (@ptrToInt(p) % 8 != 0) flow_ok = false;
            p[0] = 0x7B;
        } else {
            flow_ok = false;
        }
    }
    ti = 0;
    while (ti < 32) : (ti += 1) {
        const tp = tail[ti];
        if (tp) |p| {
            if (!gpa.gpaFree(&g, p)) flow_ok = false;
            tail[ti] = null;
        }
    }

    // Leave p8/b16/b100/b4000 live so reuse must not overlap live blocks.
    ck("free", flow_ok and gpa.gpaFree(&g, r) and
        gpa.gpaFree(&g, p1) and gpa.gpaFree(&g, p4095) and
        gpa.gpaFree(&g, z));

    const q = gpa.gpaAlloc(&g, 1000, 8);
    var reuse_ok: bool = q != null;
    if (q) |qp| {
        if (@ptrToInt(qp) % 8 != 0) reuse_ok = false;
        if (overlaps(qp, 1000, p8, 8)) reuse_ok = false;
        if (b16) |bp| {
            if (overlaps(qp, 1000, bp, 16)) reuse_ok = false;
        }
        if (b100) |bp| {
            if (overlaps(qp, 1000, bp, 100)) reuse_ok = false;
        }
        if (b4000) |bp| {
            if (overlaps(qp, 1000, bp, 4000)) reuse_ok = false;
        }
    }
    ck("reuse", reuse_ok);

    // --- a pointer outside every region is unowned ---
    var local: [8]u8 = undefined;
    const foreign: [*]u8 = local[0..].ptr;
    ck("foreign", !gpa.gpaFree(&g, foreign));

    gpa.gpaDeinit(&g);
    ck("deinit", true);

    if (g_fail == 0) {
        std.io.write("gpa small ok\n");
    } else {
        std.io.write("gpa small FAIL\n");
    }
}
