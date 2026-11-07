// stdlib_gpa_safe_xmod — STDLIB std_gpa safe-checks GREEN fixture.
//
// Contract (Phase 3.1 Layer 2, Task 5 / Amendment H1):
//   - GpaConfig.safe_checks=true adds a 4-byte small-block magic suffix just
//     before the footer (live 0xDEADBEEF, freed 0xFEEDFACE), a 0xDD fill of the
//     requested payload on free, medium page-state / large-header validation,
//     and medium-run decommit;
//   - gpaFree returns false for a double free and for a corrupted live magic,
//     touching no metadata or byte counters;
//   - live_allocs always tracks live objects; safe coalescing, splitting, and
//     resize keep the magic suffix aligned with the block end;
//   - -fsafe alone does not enable GPA checks: a throwaway fast Gpa
//     (safe_checks=false) tolerates an owned double free.
//
// GREEN (contract): deterministic byte-exact stdout ending `gpa safe ok\n`
// (RUNRC=0). Each line is `<check> 1` on success; a failed check prints 0 and
// the trailer is `gpa safe FAIL`.
const std = @import("std");

var g_fail: u32 = 0;

const LIVE: u32 = 0xDEADBEEF;
const FREED: u32 = 0xFEEDFACE;

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

fn aligned(p: [*]u8, a: usize) bool {
    return @ptrToInt(p) % a == 0;
}

// Small-block introspection (the fixture knows the packed header layout):
// bit 0 free, bits 1..16 block size, bits 17..28 requested bytes.
fn smallBlockSize(p: [*]u8) usize {
    const hp: *u32 = @intToPtr(*u32, @ptrToInt(p) - 4);
    return @intCast(usize, (hp.* & 0x0001FFFE) >> 1);
}

fn magicPtr(p: [*]u8) *u32 {
    const b: usize = @ptrToInt(p) - 4;
    return @intToPtr(*u32, b + smallBlockSize(p) - 8);
}

pub fn main() void {
    const gpa = std.gpa;

    // ================= safe_checks = true =================
    var cfg = gpa.gpaConfigTarget64();
    cfg.safe_checks = true;
    var g = gpa.gpaInit(cfg) catch {
        std.io.write("gpa safe FAIL\n");
        return;
    };
    ck("init", g.cfg.safe_checks and cfg.safe_checks);

    // --- allocate/free, live count, double-free rejection ---
    const a = must(gpa.gpaAlloc(&g, 64, 8), "alloc a");
    const b = must(gpa.gpaAlloc(&g, 200, 8), "alloc b");
    a[0] = 0xA1;
    a[63] = 0x1A;
    b[0] = 0xB1;
    b[199] = 0x1B;
    var st = gpa.gpaStats(&g);
    ck("live", st.live_allocs == 2 and st.small_bytes == 264 and
        st.medium_bytes == 0 and st.large_bytes == 0);

    ck("free", gpa.gpaFree(&g, a));
    st = gpa.gpaStats(&g);
    ck("live_after_free", st.live_allocs == 1 and st.small_bytes == 200);

    ck("double_free", !gpa.gpaFree(&g, a));
    st = gpa.gpaStats(&g);
    ck("double_free_nochange", st.live_allocs == 1 and st.small_bytes == 200 and
        b[0] == 0xB1 and b[199] == 0x1B);

    // --- a deliberately corrupted live magic is rejected with no change ---
    ck("magic_live", magicPtr(b).* == LIVE);
    magicPtr(b).* = 0x12345678;
    ck("corrupt_reject", !gpa.gpaFree(&g, b));
    st = gpa.gpaStats(&g);
    ck("corrupt_nochange", st.live_allocs == 1 and st.small_bytes == 200 and
        b[0] == 0xB1 and b[199] == 0x1B);
    magicPtr(b).* = LIVE;
    ck("corrupt_restore_free", gpa.gpaFree(&g, b));
    st = gpa.gpaStats(&g);
    ck("empty", st.live_allocs == 0 and st.small_bytes == 0);

    // --- 0xDD fill covers the requested payload, not the magic/footer ---
    const gprev = must(gpa.gpaAlloc(&g, 64, 8), "fill prev");
    const fblk = must(gpa.gpaAlloc(&g, 64, 8), "fill block");
    const gnext = must(gpa.gpaAlloc(&g, 64, 8), "fill next");
    var fi: usize = 0;
    while (fi < 64) : (fi += 1) {
        fblk[fi] = 0xAA;
    }
    ck("fill_pre", fblk[0] == 0xAA and fblk[63] == 0xAA);
    ck("fill_free", gpa.gpaFree(&g, fblk));
    var fill_ok = magicPtr(fblk).* == FREED;
    fi = 16;
    while (fi < 64) : (fi += 1) {
        if (fblk[fi] != 0xDD) fill_ok = false;
    }
    ck("fill", fill_ok);
    ck("fill_guards", gpa.gpaFree(&g, gprev) and gpa.gpaFree(&g, gnext));

    // --- medium: free/decommit, reuse the same run, double-free rejected ---
    const m1 = must(gpa.gpaAlloc(&g, 8192, 8), "medium 1");
    m1[0] = 0x31;
    m1[8191] = 0x13;
    ck("medium_free", gpa.gpaFree(&g, m1));
    st = gpa.gpaStats(&g);
    ck("medium_stats", st.medium_bytes == 0 and st.live_allocs == 0);
    const m2 = gpa.gpaAlloc(&g, 8192, 8);
    var m_ok = m2 != null;
    if (m2) |mp| {
        if (@ptrToInt(mp) != @ptrToInt(m1) or !aligned(mp, 4096)) m_ok = false;
        mp[0] = 0x32;
        mp[8191] = 0x23;
        if (mp[0] != 0x32 or mp[8191] != 0x23) m_ok = false;
    }
    ck("medium_reuse", m_ok);
    var mfree_ok = false;
    if (m2) |mp| {
        mfree_ok = gpa.gpaFree(&g, mp);
    }
    ck("medium_reuse_free", mfree_ok);

    const m3 = must(gpa.gpaAlloc(&g, 4096, 8), "medium 3");
    ck("medium_double", gpa.gpaFree(&g, m3) and !gpa.gpaFree(&g, m3));
    st = gpa.gpaStats(&g);
    ck("medium_empty", st.medium_bytes == 0 and st.live_allocs == 0);

    // --- large: mapping header magic, release/reuse, double-free rejected ---
    const l1 = must(gpa.gpaAlloc(&g, 70000, 8), "large 1");
    l1[0] = 0x41;
    l1[69999] = 0x14;
    ck("large_bytes", l1[0] == 0x41 and l1[69999] == 0x14 and aligned(l1, 4096));
    ck("large_free", gpa.gpaFree(&g, l1));
    const l2 = gpa.gpaAlloc(&g, 70000, 8);
    var l_ok = l2 != null;
    if (l2) |lp| {
        if (!aligned(lp, 4096)) l_ok = false;
        lp[0] = 0x42;
        lp[69999] = 0x24;
        if (lp[0] != 0x42 or lp[69999] != 0x24) l_ok = false;
    }
    ck("large_reuse", l_ok);
    var ld_ok = false;
    if (l2) |lp| {
        ld_ok = gpa.gpaFree(&g, lp) and !gpa.gpaFree(&g, lp);
    }
    ck("large_double", ld_ok);
    st = gpa.gpaStats(&g);
    ck("stats_empty_all", st.live_allocs == 0 and st.small_bytes == 0 and
        st.medium_bytes == 0 and st.large_bytes == 0);
    gpa.gpaDeinit(&g);
    ck("deinit", true);

    // ============ safe coalescing / split / resize ============
    var cfg2 = gpa.gpaConfigTarget64();
    cfg2.safe_checks = true;
    var gc = gpa.gpaInit(cfg2) catch {
        std.io.write("gpa safe FAIL\n");
        return;
    };

    const c1 = must(gpa.gpaAlloc(&gc, 100, 8), "coalesce 1");
    const c2 = must(gpa.gpaAlloc(&gc, 100, 8), "coalesce 2");
    const c3 = must(gpa.gpaAlloc(&gc, 100, 8), "coalesce 3");
    ck("safe_magic", magicPtr(c1).* == LIVE and magicPtr(c2).* == LIVE and
        magicPtr(c3).* == LIVE);

    ck("coalesce_free", gpa.gpaFree(&gc, c2) and gpa.gpaFree(&gc, c1) and
        gpa.gpaFree(&gc, c3));

    // Split the coalesced run: the allocated part is live, the remainder is
    // a free block carrying the freed magic at its own end.
    const n1 = must(gpa.gpaAlloc(&gc, 300, 8), "split realloc");
    n1[0] = 0x51;
    n1[299] = 0x15;
    ck("split", magicPtr(n1).* == LIVE and n1[0] == 0x51 and n1[299] == 0x15);
    ck("split_free", gpa.gpaFree(&gc, n1));

    // Resize in place keeps the live magic (capacity unchanged); a growing
    // move allocates a live magic and frees the old block (freed magic).
    const r1 = must(gpa.gpaAlloc(&gc, 40, 8), "resize block");
    r1[0] = 0x61;
    r1[39] = 0x16;
    const r2 = gpa.gpaResize(&gc, r1, 44, 8);
    var ri_ok = r2 != null;
    if (r2) |rr| {
        ri_ok = rr == r1 and magicPtr(rr).* == LIVE and
            rr[0] == 0x61 and rr[39] == 0x16;
    }
    ck("resize_inplace", ri_ok);

    const r3 = gpa.gpaResize(&gc, r1, 200, 8);
    var rm_ok = r3 != null;
    if (r3) |rr| {
        rm_ok = magicPtr(rr).* == LIVE and rr[0] == 0x61 and rr[39] == 0x16;
    }
    ck("resize_move", rm_ok);
    var rfree_ok = false;
    if (r3) |rr| {
        rfree_ok = gpa.gpaFree(&gc, rr);
    }
    ck("resize_free", rfree_ok);

    // --- free the region's blocks; a later allocation still works ---
    const post = must(gpa.gpaAlloc(&gc, 500, 8), "region realloc");
    post[0] = 0x71;
    post[499] = 0x17;
    ck("region_reuse", magicPtr(post).* == LIVE and
        post[0] == 0x71 and post[499] == 0x17);
    ck("region_free", gpa.gpaFree(&gc, post));
    st = gpa.gpaStats(&gc);
    ck("safe_empty", st.live_allocs == 0 and st.small_bytes == 0);
    gpa.gpaDeinit(&gc);
    ck("safe_deinit", true);

    // ===== -fsafe alone does not enable checks (runs last: corrupts) =====
    var fcfg = gpa.gpaConfigTarget64();
    var gf = gpa.gpaInit(fcfg) catch {
        std.io.write("gpa safe FAIL\n");
        return;
    };
    const fa = must(gpa.gpaAlloc(&gf, 64, 8), "fast alloc");
    const fast_first = gpa.gpaFree(&gf, fa);
    const fast_second = gpa.gpaFree(&gf, fa);
    ck("fast_tolerated", !gf.cfg.safe_checks and fast_first and fast_second);
    gpa.gpaDeinit(&gf);
    ck("fast_deinit", true);

    if (g_fail == 0) {
        std.io.write("gpa safe ok\n");
    } else {
        std.io.write("gpa safe FAIL\n");
    }
}
