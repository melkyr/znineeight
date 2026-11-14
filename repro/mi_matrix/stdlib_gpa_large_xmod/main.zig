// stdlib_gpa_large_xmod — STDLIB std_gpa direct large-mapping GREEN fixture.
//
// Contract (Phase 3.1 Layer 2, Task 4): sizes above medium_max (64 KiB for
// target64) take direct page mappings, return page-aligned data, support
// zeroed allocation, reject align > 4096, and report per-tier stats with
// live_allocs tracked in all modes.
//
// GREEN (contract): deterministic byte-exact stdout ending `gpa large ok\n`
// (RUNRC=0). Each line is `<check> 1` on success; a failed check prints 0 and
// the trailer is `gpa large FAIL`.
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

fn aligned(p: [*]u8, a: usize) bool {
    return @ptrToInt(p) % a == 0;
}

fn zeroes(p: [*]u8, n: usize) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (p[i] != 0) return false;
    }
    return true;
}

pub fn main() void {
    const gpa = std.gpa;

    var cfg = gpa.gpaConfigTarget64();
    var g = gpa.gpaInit(cfg) catch {
        std.io.write("gpa large FAIL\n");
        return;
    };
    ck("init", true);
    ck("profile", cfg.target == gpa.TargetProfile.target64 and
        cfg.medium_max == 65536 and cfg.chunk_bytes == 2097152 and
        !cfg.safe_checks and !cfg.shuffle);

    // --- every constructor matches the table; explicit fields override target ---
    const c32 = gpa.gpaConfigTarget32();
    const c64 = gpa.gpaConfigTarget64();
    const c128 = gpa.gpaConfigTarget128();
    const c256 = gpa.gpaConfigTarget256();
    const c512 = gpa.gpaConfigTarget512();
    const cmod = gpa.gpaConfigTargetModern();
    const cdef = gpa.gpaConfigDefault();
    var prof_ok = cdef.target == gpa.TargetProfile.target64 and
        cdef.medium_max == 65536 and cdef.chunk_bytes == 2097152 and
        c32.medium_max == 65536 and c32.chunk_bytes == 1048576 and
        c64.medium_max == 65536 and c64.chunk_bytes == 2097152 and
        c128.medium_max == 131072 and c128.chunk_bytes == 4194304 and
        c256.medium_max == 262144 and c256.chunk_bytes == 8388608 and
        c512.medium_max == 262144 and c512.chunk_bytes == 16777216 and
        cmod.medium_max == 1048576 and cmod.chunk_bytes == 16777216;
    var cover = gpa.gpaConfigTarget32();
    cover.medium_max = 1048576;
    cover.chunk_bytes = 16777216;
    var gover = gpa.gpaInit(cover) catch {
        std.io.write("gpa large FAIL\n");
        return;
    };
    prof_ok = prof_ok and gover.cfg.medium_max == 1048576 and
        gover.cfg.chunk_bytes == 16777216 and
        gover.cfg.target == gpa.TargetProfile.target32;
    gpa.gpaDeinit(&gover);
    ck("profiles", prof_ok);

    // --- direct mappings above medium_max, both natural and page align ---
    const p = must(gpa.gpaAlloc(&g, 65537, 8), "alloc 65537");
    const pm = must(gpa.gpaAlloc(&g, 1048576, 8), "alloc 1 MiB");
    const pa = must(gpa.gpaAlloc(&g, 70000, 4096), "alloc large align 4096");
    ck("alloc", p != ZERO and pm != ZERO and pa != ZERO and
        aligned(p, 4096) and aligned(pm, 4096) and aligned(pa, 4096));

    p[0] = 0x11;
    p[65536] = 0x81;
    pm[0] = 0x22;
    pm[1048575] = 0x82;
    pa[0] = 0x33;
    pa[69999] = 0x83;
    ck("bytes", p[0] == 0x11 and p[65536] == 0x81 and
        pm[0] == 0x22 and pm[1048575] == 0x82 and
        pa[0] == 0x33 and pa[69999] == 0x83);

    var st = gpa.gpaStats(&g);
    ck("stats_large", st.small_bytes == 0 and st.medium_bytes == 0 and
        st.large_bytes == 65537 + 1048576 + 70000 and
        st.live_allocs == 3 and st.chunks == 0 and st.regions == 0);

    const z = must(gpa.gpaAllocZeroed(&g, 200000, 8), "allocZeroed 200000");
    ck("zero", aligned(z, 4096) and zeroes(z, 200000));

    ck("reject", gpa.gpaAlloc(&g, 65537, 8192) == null);
    ck("freez", gpa.gpaFree(&g, z));

    // --- free and reallocate: the mapping list must recycle cleanly ---
    ck("free", gpa.gpaFree(&g, p) and gpa.gpaFree(&g, pm) and gpa.gpaFree(&g, pa));
    st = gpa.gpaStats(&g);
    ck("stats_empty", st.small_bytes == 0 and st.medium_bytes == 0 and
        st.large_bytes == 0 and st.live_allocs == 0 and
        st.chunks == 0 and st.regions == 0);

    const p2 = must(gpa.gpaAlloc(&g, 65537, 8), "realloc 65537");
    p2[0] = 0x71;
    p2[65536] = 0x17;
    ck("reuse", aligned(p2, 4096) and p2[0] == 0x71 and p2[65536] == 0x17);

    // --- per-tier stats after one small, one medium, one large live object ---
    const s = must(gpa.gpaAlloc(&g, 100, 8), "stats small");
    const m = must(gpa.gpaAlloc(&g, 8192, 8), "stats medium");
    s[0] = 0xAA;
    m[0] = 0xBB;
    m[8191] = 0xCC;
    st = gpa.gpaStats(&g);
    ck("stats_tiers", st.small_bytes == 100 and st.medium_bytes == 8192 and
        st.large_bytes == 65537 and st.live_allocs == 3 and
        st.chunks == 1 and st.regions == 1);

    ck("free_tiers", gpa.gpaFree(&g, s) and gpa.gpaFree(&g, m) and
        gpa.gpaFree(&g, p2));
    st = gpa.gpaStats(&g);
    ck("stats_owned", st.small_bytes == 0 and st.medium_bytes == 0 and
        st.large_bytes == 0 and st.live_allocs == 0 and
        st.chunks == 1 and st.regions == 1);

    gpa.gpaDeinit(&g);
    ck("deinit", true);

    if (g_fail == 0) {
        std.io.write("gpa large ok\n");
    } else {
        std.io.write("gpa large FAIL\n");
    }
}
