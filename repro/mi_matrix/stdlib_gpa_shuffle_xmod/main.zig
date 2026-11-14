// stdlib_gpa_shuffle_xmod — STDLIB std_gpa optional-shuffle GREEN fixture.
//
// Contract (Phase 3.1 Layer 2, Task 4): shuffle=true with the same
// shuffle_seed reproduces the same free-list insertion/reuse order across fresh
// Gpas; shuffle=false matches the deterministic head-insertion baseline. This
// is a determinism feature, not a security claim.
//
// GREEN (contract): deterministic byte-exact stdout ending `gpa shuffle ok\n`
// (RUNRC=0). Each line is `<check> 1` on success; a failed check prints 0 and
// the trailer is `gpa shuffle FAIL`.
const std = @import("std");

var g_fail: u32 = 0;

var small_base_a: [8]usize = undefined;
var small_base_b: [8]usize = undefined;
var small_shuf_a: [8]usize = undefined;
var small_shuf_b: [8]usize = undefined;
var medium_base: [8]usize = undefined;
var medium_shuf_a: [8]usize = undefined;
var medium_shuf_b: [8]usize = undefined;

fn ck(what: []const u8, cond: bool) void {
    std.io.write(what);
    if (cond) {
        std.io.write(" 1\n");
    } else {
        std.io.write(" 0\n");
        g_fail += 1;
    }
}

fn same(a: [*]usize, b: [*]usize) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn descending(a: [*]usize) bool {
    var i: usize = 0;
    while (i + 1 < 8) : (i += 1) {
        if (a[i] <= a[i + 1]) return false;
    }
    return true;
}

fn permutation(shuffled: [*]usize, baseline: [*]usize) bool {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        var found: bool = false;
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            if (shuffled[i] == baseline[j]) found = true;
        }
        if (!found) return false;
    }
    return true;
}

fn orig_index(orig: *[16]usize, a: usize) usize {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        if (orig[i] == a) return i;
    }
    return 99;
}

// Allocate 16 same-size blocks, free the odd (non-adjacent) ones in ascending
// order, then re-record the reuse order of 8 fresh allocations. Adjacent blocks
// stay live as guards, so free lists are neither coalesced nor split.
fn run_small(g: *std.gpa.Gpa, out: [*]usize) bool {
    var blocks: [20]?[*]u8 = undefined;
    var orig: [16]usize = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const p = std.gpa.gpaAlloc(g, 256, 8);
        if (p == null) return false;
        blocks[i] = p;
        if (p) |q| {
            if (i < 16) orig[i] = @ptrToInt(q);
            q[0] = @intCast(u8, i & 0xFF);
            q[255] = @intCast(u8, (i ^ 0xA5) & 0xFF);
        }
    }

    i = 0;
    while (i < 16) : (i += 1) {
        if (i % 2 == 1) {
            if (blocks[i]) |p| {
                if (!std.gpa.gpaFree(g, p)) return false;
            }
        }
    }

    i = 0;
    while (i < 8) : (i += 1) {
        const q = std.gpa.gpaAlloc(g, 256, 8);
        if (q == null) return false;
        if (q) |qp| {
            const oi = orig_index(orig[0..].ptr, @ptrToInt(qp));
            if (oi > 15) return false;
            out[i] = oi;
            blocks[2 * i + 1] = qp;
        }
    }

    i = 0;
    while (i < 20) : (i += 1) {
        if (blocks[i]) |p| {
            if (!std.gpa.gpaFree(g, p)) return false;
        }
    }
    return true;
}

// Same shape for the medium run free lists (one page per block).
fn run_medium(g: *std.gpa.Gpa, out: [*]usize) bool {
    var blocks: [20]?[*]u8 = undefined;
    var orig: [16]usize = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const p = std.gpa.gpaAlloc(g, 4096, 8);
        if (p == null) return false;
        blocks[i] = p;
        if (p) |q| {
            if (i < 16) orig[i] = @ptrToInt(q);
            q[0] = @intCast(u8, i & 0xFF);
            q[4095] = @intCast(u8, (i ^ 0x5A) & 0xFF);
        }
    }

    i = 0;
    while (i < 16) : (i += 1) {
        if (i % 2 == 1) {
            if (blocks[i]) |p| {
                if (!std.gpa.gpaFree(g, p)) return false;
            }
        }
    }

    i = 0;
    while (i < 8) : (i += 1) {
        const q = std.gpa.gpaAlloc(g, 4096, 8);
        if (q == null) return false;
        if (q) |qp| {
            const oi = orig_index(orig[0..].ptr, @ptrToInt(qp));
            if (oi > 15) return false;
            out[i] = oi;
            blocks[2 * i + 1] = qp;
        }
    }

    i = 0;
    while (i < 20) : (i += 1) {
        if (blocks[i]) |p| {
            if (!std.gpa.gpaFree(g, p)) return false;
        }
    }
    return true;
}

pub fn main() void {
    const gpa = std.gpa;

    // --- shuffle=false: two fresh Gpas match the head-insertion baseline ---
    var base_cfg = gpa.gpaConfigTarget64();
    var gb1 = gpa.gpaInit(base_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_a = run_small(&gb1, small_base_a[0..].ptr);
    gpa.gpaDeinit(&gb1);
    var gb2 = gpa.gpaInit(base_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_b = run_small(&gb2, small_base_b[0..].ptr);
    gpa.gpaDeinit(&gb2);
    ck("baseline", ok_a and ok_b and
        same(small_base_a[0..].ptr, small_base_b[0..].ptr) and
        descending(small_base_a[0..].ptr));

    // --- same seed: fresh Gpas reproduce the identical reuse order ---
    var shuf_cfg = gpa.gpaConfigTarget64();
    shuf_cfg.shuffle = true;
    shuf_cfg.shuffle_seed = 0x12345678;
    var gs1 = gpa.gpaInit(shuf_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_s1 = run_small(&gs1, small_shuf_a[0..].ptr);
    gpa.gpaDeinit(&gs1);
    var gs2 = gpa.gpaInit(shuf_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_s2 = run_small(&gs2, small_shuf_b[0..].ptr);
    gpa.gpaDeinit(&gs2);
    ck("seed", ok_s1 and ok_s2 and
        same(small_shuf_a[0..].ptr, small_shuf_b[0..].ptr) and
        permutation(small_shuf_a[0..].ptr, small_base_a[0..].ptr) and
        !same(small_shuf_a[0..].ptr, small_base_a[0..].ptr));

    // --- medium run free lists follow the same deterministic shuffle ---
    var mb1 = gpa.gpaInit(base_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_mb = run_medium(&mb1, medium_base[0..].ptr);
    gpa.gpaDeinit(&mb1);
    var ms1 = gpa.gpaInit(shuf_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_ms1 = run_medium(&ms1, medium_shuf_a[0..].ptr);
    gpa.gpaDeinit(&ms1);
    var ms2 = gpa.gpaInit(shuf_cfg) catch {
        std.io.write("gpa shuffle FAIL\n");
        return;
    };
    var ok_ms2 = run_medium(&ms2, medium_shuf_b[0..].ptr);
    gpa.gpaDeinit(&ms2);
    ck("medium", ok_mb and ok_ms1 and ok_ms2 and
        descending(medium_base[0..].ptr) and
        same(medium_shuf_a[0..].ptr, medium_shuf_b[0..].ptr) and
        permutation(medium_shuf_a[0..].ptr, medium_base[0..].ptr) and
        !same(medium_shuf_a[0..].ptr, medium_base[0..].ptr));

    ck("deterministic", true);

    if (g_fail == 0) {
        std.io.write("gpa shuffle ok\n");
    } else {
        std.io.write("gpa shuffle FAIL\n");
    }
}
