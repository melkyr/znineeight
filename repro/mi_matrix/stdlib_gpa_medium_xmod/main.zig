// stdlib_gpa_medium_xmod — STDLIB std_gpa page-run medium-tier GREEN fixture.
//
// Contract (Phase 3.1 Layer 2, Task 3): 2 MiB chunks, 4 KiB page runs, split and
// coalesce, mixed free order, resize, and align > 8 routing through page-aligned
// medium runs. The medium tier covers 4096..medium_max (64 KiB for target64).
//
// GREEN (contract): deterministic byte-exact stdout ending `gpa medium ok\n`
// (RUNRC=0). Each line is `<check> 1` on success; a failed check prints 0 and
// the trailer is `gpa medium FAIL`.
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

fn overlaps(a: [*]u8, alen: usize, b: [*]u8, blen: usize) bool {
    const a0: usize = @ptrToInt(a);
    const b0: usize = @ptrToInt(b);
    const a1: usize = a0 + alen;
    const b1: usize = b0 + blen;
    return a0 < b1 and b0 < a1;
}

fn aligned(p: [*]u8, a: usize) bool {
    return @ptrToInt(p) % a == 0;
}

pub fn main() void {
    const gpa = std.gpa;

    var cfg = gpa.gpaConfigTarget64();
    var g = gpa.gpaInit(cfg) catch {
        std.io.write("gpa medium FAIL\n");
        return;
    };
    ck("init", true);

    // --- medium sizes 4096..65536, marker at both ends ---
    const p4 = must(gpa.gpaAlloc(&g, 4096, 8), "alloc 4096");
    const p8 = must(gpa.gpaAlloc(&g, 8192, 8), "alloc 8192");
    const p16 = must(gpa.gpaAlloc(&g, 16384, 8), "alloc 16384");
    const p64 = must(gpa.gpaAlloc(&g, 65536, 8), "alloc 65536");
    ck("alloc", p4 != ZERO and p8 != ZERO and p16 != ZERO and p64 != ZERO);

    p4[0] = 0x11;
    p4[4095] = 0xE1;
    p8[0] = 0x22;
    p8[8191] = 0xE2;
    p16[0] = 0x33;
    p16[16383] = 0xE3;
    p64[0] = 0x44;
    p64[65535] = 0xE4;
    ck("bytes", p4[0] == 0x11 and p4[4095] == 0xE1 and
        p8[0] == 0x22 and p8[8191] == 0xE2 and
        p16[0] == 0x33 and p16[16383] == 0xE3 and
        p64[0] == 0x44 and p64[65535] == 0xE4);

    // --- align > 8 routing: small requests occupy page-aligned runs ---
    const a16 = must(gpa.gpaAlloc(&g, 16, 16), "alloc align 16");
    const a4096 = must(gpa.gpaAlloc(&g, 16, 4096), "alloc align 4096");
    ck("align", aligned(p4, 4096) and aligned(p8, 4096) and
        aligned(p16, 4096) and aligned(p64, 4096) and
        aligned(a16, 16) and aligned(a4096, 4096));

    // --- resize 4096 -> 8192 keeps the original bytes ---
    const rp = must(gpa.gpaResize(&g, p4, 8192, 8), "resize 4096->8192");
    ck("resize", aligned(rp, 8) and rp[0] == 0x11 and rp[4095] == 0xE1);

    // --- mixed-order free; reallocate and verify reuse/coalescing ---
    ck("free", gpa.gpaFree(&g, p16) and gpa.gpaFree(&g, p8) and
        gpa.gpaFree(&g, p64) and gpa.gpaFree(&g, rp));

    const q4 = must(gpa.gpaAlloc(&g, 4096, 8), "reuse 4096");
    const q8 = must(gpa.gpaAlloc(&g, 8192, 8), "reuse 8192");
    const q16 = must(gpa.gpaAlloc(&g, 16384, 8), "reuse 16384");
    const q64 = must(gpa.gpaAlloc(&g, 65536, 8), "reuse 65536");
    var reuse_ok: bool = aligned(q4, 4096) and aligned(q8, 4096) and
        aligned(q16, 4096) and aligned(q64, 4096);
    if (overlaps(q4, 4096, a16, 16) or overlaps(q4, 4096, a4096, 16)) reuse_ok = false;
    if (overlaps(q8, 8192, a16, 16) or overlaps(q8, 8192, a4096, 16)) reuse_ok = false;
    if (overlaps(q16, 16384, a16, 16) or overlaps(q16, 16384, a4096, 16)) reuse_ok = false;
    if (overlaps(q64, 65536, a16, 16) or overlaps(q64, 65536, a4096, 16)) reuse_ok = false;
    if (overlaps(q4, 4096, q8, 8192)) reuse_ok = false;
    if (overlaps(q4, 4096, q16, 16384)) reuse_ok = false;
    if (overlaps(q4, 4096, q64, 65536)) reuse_ok = false;
    if (overlaps(q8, 8192, q16, 16384)) reuse_ok = false;
    if (overlaps(q8, 8192, q64, 65536)) reuse_ok = false;
    if (overlaps(q16, 16384, q64, 65536)) reuse_ok = false;
    q4[0] = 0x51;
    q4[4095] = 0x15;
    q8[0] = 0x52;
    q8[8191] = 0x25;
    q16[0] = 0x53;
    q16[16383] = 0x35;
    q64[0] = 0x54;
    q64[65535] = 0x45;
    if (q4[0] != 0x51 or q4[4095] != 0x15) reuse_ok = false;
    if (q8[0] != 0x52 or q8[8191] != 0x25) reuse_ok = false;
    if (q16[0] != 0x53 or q16[16383] != 0x35) reuse_ok = false;
    if (q64[0] != 0x54 or q64[65535] != 0x45) reuse_ok = false;
    ck("reuse", reuse_ok);

    // --- 1000-op medium stress: no duplicate live pointers, no corruption ---
    var live: [8]?[*]u8 = undefined;
    var sizes: [8]usize = undefined;
    var marks0: [8]u8 = undefined;
    var marks1: [8]u8 = undefined;
    var initslot: usize = 0;
    while (initslot < 8) : (initslot += 1) {
        live[initslot] = null;
        sizes[initslot] = 0;
        marks0[initslot] = 0;
        marks1[initslot] = 0;
    }

    var stress_ok: bool = true;
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const slot = i % 8;
        if (live[slot]) |old| {
            if (old[0] != marks0[slot] or old[sizes[slot] - 1] != marks1[slot]) {
                stress_ok = false;
            }
            if (!gpa.gpaFree(&g, old)) stress_ok = false;
            live[slot] = null;
        }

        const sz: usize = 4096 + (i % 4) * 4096;
        const np = gpa.gpaAlloc(&g, sz, 8);
        if (np) |p| {
            var j: usize = 0;
            while (j < 8) : (j += 1) {
                if (live[j]) |q| {
                    if (q == p) stress_ok = false;
                    if (overlaps(p, sz, q, sizes[j])) stress_ok = false;
                }
            }
            const m0: u8 = @intCast(u8, (i & 0xFF) ^ 0x5A);
            const m1: u8 = @intCast(u8, (i & 0xFF) ^ 0xA5);
            p[0] = m0;
            p[sz - 1] = m1;
            live[slot] = p;
            sizes[slot] = sz;
            marks0[slot] = m0;
            marks1[slot] = m1;
        } else {
            stress_ok = false;
            break;
        }
    }

    var s: usize = 0;
    while (s < 8) : (s += 1) {
        if (live[s]) |p| {
            if (p[0] != marks0[s] or p[sizes[s] - 1] != marks1[s]) stress_ok = false;
            if (!gpa.gpaFree(&g, p)) stress_ok = false;
            live[s] = null;
        }
    }

    // --- free the remaining allocations, then split the whole-chunk run ---
    if (!gpa.gpaFree(&g, q4)) stress_ok = false;
    if (!gpa.gpaFree(&g, q8)) stress_ok = false;
    if (!gpa.gpaFree(&g, q16)) stress_ok = false;
    if (!gpa.gpaFree(&g, q64)) stress_ok = false;
    if (!gpa.gpaFree(&g, a16)) stress_ok = false;
    if (!gpa.gpaFree(&g, a4096)) stress_ok = false;

    const w4 = must(gpa.gpaAlloc(&g, 4096, 8), "whole 4096");
    const w8 = must(gpa.gpaAlloc(&g, 8192, 8), "whole 8192");
    const w16 = must(gpa.gpaAlloc(&g, 16384, 8), "whole 16384");
    const w64 = must(gpa.gpaAlloc(&g, 65536, 8), "whole 65536");
    w4[0] = 0x61;
    w4[4095] = 0x16;
    w8[0] = 0x62;
    w8[8191] = 0x26;
    w16[0] = 0x63;
    w16[16383] = 0x36;
    w64[0] = 0x64;
    w64[65535] = 0x46;
    if (w4[0] != 0x61 or w4[4095] != 0x16) stress_ok = false;
    if (w8[0] != 0x62 or w8[8191] != 0x26) stress_ok = false;
    if (w16[0] != 0x63 or w16[16383] != 0x36) stress_ok = false;
    if (w64[0] != 0x64 or w64[65535] != 0x46) stress_ok = false;
    if (overlaps(w4, 4096, w8, 8192)) stress_ok = false;
    if (overlaps(w4, 4096, w16, 16384)) stress_ok = false;
    if (overlaps(w4, 4096, w64, 65536)) stress_ok = false;
    if (overlaps(w8, 8192, w16, 16384)) stress_ok = false;
    if (overlaps(w8, 8192, w64, 65536)) stress_ok = false;
    if (overlaps(w16, 16384, w64, 65536)) stress_ok = false;

    // --- coalescing-only sequence: fill a fresh chunk, then merge two runs ---
    // 63 * 8 pages = 504 pages, leaving < 8 pages of the 509-page target64
    // chunk. Freeing two adjacent 8-page blocks only yields a 16-page run if
    // freeMedium coalesces; a build without coalescing cannot serve the
    // 65536-byte request from this chunk (it would have to make a new one).
    var cfg2 = gpa.gpaConfigTarget64();
    var g2 = gpa.gpaInit(cfg2) catch @panic("coalesce init");
    var cb: [64]?[*]u8 = undefined;
    var ci: usize = 0;
    while (ci < 64) : (ci += 1) {
        cb[ci] = null;
    }
    ci = 0;
    while (ci < 63) : (ci += 1) {
        const bp = must(gpa.gpaAlloc(&g2, 32768, 8), "coalesce fill");
        cb[ci] = bp;
        bp[0] = @intCast(u8, ci & 0xFF);
        bp[32767] = @intCast(u8, (ci ^ 0xA5) & 0xFF);
    }

    if (cb[0]) |b0| {
        if (cb[1]) |b1| {
            if (@ptrToInt(b1) != @ptrToInt(b0) + 32768) stress_ok = false;
            if (!gpa.gpaFree(&g2, b0)) stress_ok = false;
            if (!gpa.gpaFree(&g2, b1)) stress_ok = false;
            cb[0] = null;
            cb[1] = null;

            const c16 = gpa.gpaAlloc(&g2, 65536, 8);
            if (c16) |cp| {
                // The merge must reuse the freed adjacent run, not a new chunk.
                if (@ptrToInt(cp) != @ptrToInt(b0)) stress_ok = false;
                var k: usize = 2;
                while (k < 63) : (k += 1) {
                    if (cb[k]) |q| {
                        if (overlaps(cp, 65536, q, 32768)) stress_ok = false;
                    }
                }
                cp[0] = 0xC1;
                cp[65535] = 0x1C;
                if (cp[0] != 0xC1 or cp[65535] != 0x1C) stress_ok = false;
                if (!gpa.gpaFree(&g2, cp)) stress_ok = false;
                const c16b = gpa.gpaAlloc(&g2, 65536, 8);
                if (c16b) |cp2| {
                    if (cp2[0] != 0xC1 or cp2[65535] != 0x1C) stress_ok = false;
                    k = 2;
                    while (k < 63) : (k += 1) {
                        if (cb[k]) |q| {
                            if (overlaps(cp2, 65536, q, 32768)) stress_ok = false;
                        }
                    }
                    if (!gpa.gpaFree(&g2, cp2)) stress_ok = false;
                } else {
                    stress_ok = false;
                }
            } else {
                stress_ok = false;
            }
        } else {
            stress_ok = false;
        }
    } else {
        stress_ok = false;
    }
    gpa.gpaDeinit(&g2);
    ck("stress", stress_ok);

    // --- a pointer outside every chunk/region is unowned ---
    var local: [8]u8 = undefined;
    const foreign: [*]u8 = local[0..].ptr;
    ck("foreign", !gpa.gpaFree(&g, foreign));

    gpa.gpaDeinit(&g);
    ck("deinit", true);

    if (g_fail == 0) {
        std.io.write("gpa medium ok\n");
    } else {
        std.io.write("gpa medium FAIL\n");
    }
}
