// stdlib_gpa_resize_xmod — STDLIB std_gpa resize GREEN fixture.
//
// Contract (Phase 3.1 Layer 2, Task 4): grow/shrink small, medium, and large
// blocks with contents surviving; a stricter align forces the aligned
// allocate/copy/free path; resize-to-zero and the u64 overflow recipe leave the
// old pointer valid.
//
// GREEN (contract): deterministic byte-exact stdout ending `gpa resize ok\n`
// (RUNRC=0). Each line is `<check> 1` on success; a failed check prints 0 and
// the trailer is `gpa resize FAIL`.
const std = @import("std");

var g_fail: u32 = 0;

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

fn fill(p: [*]u8, n: usize) void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        p[i] = @intCast(u8, i & 0xFF);
    }
}

fn matches(p: [*]u8, n: usize) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (p[i] != @intCast(u8, i & 0xFF)) return false;
    }
    return true;
}

pub fn main() void {
    const gpa = std.gpa;

    var cfg = gpa.gpaConfigTarget64();
    var g = gpa.gpaInit(cfg) catch {
        std.io.write("gpa resize FAIL\n");
        return;
    };
    ck("init", true);

    // --- small grow and shrink; both stay in the small tier ---
    const sp = must(gpa.gpaAlloc(&g, 1000, 8), "small alloc");
    fill(sp, 1000);
    const sr = must(gpa.gpaResize(&g, sp, 2000, 8), "small grow");
    const s_ok = aligned(sr, 8) and matches(sr, 1000);
    const ss = must(gpa.gpaResize(&g, sr, 500, 8), "small shrink");
    ck("small", s_ok and aligned(ss, 8) and matches(ss, 500));
    ck("small_free", gpa.gpaFree(&g, ss));

    // --- medium grow (new run) then shrink (same run), contents survive ---
    const mp = must(gpa.gpaAlloc(&g, 8192, 8), "medium alloc");
    fill(mp, 8192);
    const mr = must(gpa.gpaResize(&g, mp, 16384, 8), "medium grow");
    const m_ok = aligned(mr, 4096) and matches(mr, 8192);
    const ms = must(gpa.gpaResize(&g, mr, 4096, 8), "medium shrink");
    ck("medium", m_ok and aligned(ms, 4096) and matches(ms, 4096));
    ck("medium_free", gpa.gpaFree(&g, ms));

    // --- large grow (new mapping) then shrink (same mapping) ---
    const lp = must(gpa.gpaAlloc(&g, 100000, 8), "large alloc");
    fill(lp, 100000);
    const lr = must(gpa.gpaResize(&g, lp, 200000, 8), "large grow");
    const l_ok = aligned(lr, 4096) and matches(lr, 100000);
    const ls = must(gpa.gpaResize(&g, lr, 80000, 8), "large shrink");
    ck("large", l_ok and aligned(ls, 4096) and matches(ls, 80000));
    ck("large_free", gpa.gpaFree(&g, ls));

    // --- stricter align forces the aligned allocate/copy/free path ---
    const ap = must(gpa.gpaAlloc(&g, 100, 8), "align alloc");
    fill(ap, 100);
    const ar = must(gpa.gpaResize(&g, ap, 100, 4096), "align resize");
    ck("align", aligned(ar, 4096) and matches(ar, 100));
    ck("align_free", gpa.gpaFree(&g, ar));

    // --- deterministic u64 overflow recipe: old pointer stays valid ---
    const fp = must(gpa.gpaAlloc(&g, 100, 8), "overflow alloc");
    fp[0] = 0xAB;
    fp[99] = 0xCD;
    const fr = gpa.gpaResize(&g, fp, 0xFFFFFFF0, 8);
    ck("overflow", fr == null and fp[0] == 0xAB and fp[99] == 0xCD);

    // --- resize to zero returns null and leaves the block valid ---
    const zr = gpa.gpaResize(&g, fp, 0, 8);
    fp[1] = 0xEF;
    ck("zero", zr == null and fp[0] == 0xAB and fp[1] == 0xEF);
    ck("overflow_free", gpa.gpaFree(&g, fp));

    gpa.gpaDeinit(&g);
    ck("deinit", true);

    if (g_fail == 0) {
        std.io.write("gpa resize ok\n");
    } else {
        std.io.write("gpa resize FAIL\n");
    }
}
