// stdlib_capture_sibling_reuse_xmod — Task 10D positive runtime fixture.
//
// A plain local declared after a same-named `for` capture in a SIBLING scope
// must introduce a DISTINCT variable (official Zig 0.15.2 parity). Pre-fix
// (`captureShadowShouldRedirect`, sf/src/lower.zig), the source->synth redirect
// table `capture_shadow` leaked across sibling scopes and the guard used a
// depth-only heuristic, so the later local aliased the stale capture temp: its
// declaration + initializer were dropped and every use read/wrote the old
// loop variable (canonical r3 probe: Zig `c7=6 g7=2` vs pre-fix `c7=3 g7=5`).
//
// Covers (stdlib pin 216 -> 217):
//   * canonical shape — early sibling `var j` -> renamed nested `|j|` capture
//     -> later sibling `for`-body `var j` (r3: c7=6 g7=2)
//   * later sibling `while`-body `var j` (t1)
//   * later sibling `while`-body `const j` (t5)
//   * later sibling `for`-body `var j` (t7)
//   * two renamed sibling captures before the later `var j` (t9)
//   * bare-block `var j` at a shallower depth (t11)
// Controls that must stay unchanged:
//   * same-depth nested block (t6) / capture used after a nested loop (t2)
//   * different-name local (t10) / no earlier same-name local (r10)
//   * `while (opt) |j|` / `if (opt) |j|` capture analogues (t4/t12)
//   * cross-function name reuse (synth-scope-not-in-chain fallback)
//
// Every aggregate is `@panic`-guarded, so a wrong value traps (rc 133) instead
// of printing as if correct. Golden from the FIXED compiler, 3x byte-exact,
// cross-checked against a Zig 0.15.2 twin (`std.debug.print`).
//
// NOTE: this fixture deliberately does NOT use `@intCast` on any capture — a
// separate pre-existing defect emits invalid C for that shape (out of scope).
const std = @import("std");

fn pick(x: u32) ?u32 {
    if (x == 0) return null;
    return x + 1;
}

fn xfn_a() u32 {
    var a: u32 = 0;
    var sum: u32 = 0;
    while (a < 2) : (a += 1) {
        var j: u32 = 3;
        sum += j;
        j += 1;
    }
    var cap: u32 = 0;
    for (0..2) |i| {
        for (0..2) |j| {
            _ = i;
            _ = j;
            cap += 1;
        }
    }
    return sum + cap;
}

fn xfn_b() u32 {
    var b: u32 = 0;
    var sum: u32 = 0;
    while (b < 2) : (b += 1) {
        var j: u32 = 4;
        sum += j;
        j += 1;
    }
    return sum;
}

pub fn main() void {
    // --- canonical r3 shape -------------------------------------------------
    var s1a: u32 = 0;
    var s1b: u32 = 0;
    while (s1a < 3) : (s1a += 1) {
        var j: u32 = 0;
        while (j < 2) : (j += 1) {
            s1b += 1;
        }
    }
    var cap1: u32 = 0;
    for (0..3) |i| {
        for (0..3) |j| {
            _ = i;
            _ = j;
            cap1 += 1;
        }
    }
    var c7: u32 = 0;
    var g7: u32 = 0;
    outer6: for (0..5) |i| {
        var j: u32 = 0;
        while (j < 3) : (j += 1) {
            if (i == 2 and j == 0) break :outer6;
            c7 += 1;
        }
        g7 += 1;
    }
    if (s1b != 6 or cap1 != 9 or c7 != 6 or g7 != 2) {
        @panic("canonical sibling-reuse guard failed");
    }

    // --- later sibling while-body `var j` (t1) ------------------------------
    var post1: u32 = 0;
    var b1: u32 = 0;
    while (b1 < 3) : (b1 += 1) {
        var j: u32 = 9;
        post1 += j;
        j += 1;
        post1 += j;
    }
    if (post1 != 57) {
        @panic("while-body var guard failed");
    }

    // --- later sibling while-body `const j` (t5) ----------------------------
    var post2: u32 = 0;
    var b2: u32 = 0;
    while (b2 < 3) : (b2 += 1) {
        const j: u32 = 9;
        post2 += j;
    }
    if (post2 != 27) {
        @panic("while-body const guard failed");
    }

    // --- later sibling for-body `var j` (t7) --------------------------------
    var post3: u32 = 0;
    for (0..3) |i| {
        _ = i;
        var j: u32 = 5;
        post3 += j;
        j += 1;
    }
    if (post3 != 15) {
        @panic("for-body var guard failed");
    }

    // --- two renamed sibling captures before the later `var j` (t9) ---------
    var cap2: u32 = 0;
    for (0..2) |i| {
        for (0..2) |j| {
            _ = i;
            _ = j;
            cap2 += 1;
        }
    }
    var cap3: u32 = 0;
    for (0..2) |i| {
        for (0..2) |j| {
            _ = i;
            _ = j;
            cap3 += 1;
        }
    }
    var post4: u32 = 0;
    var b4: u32 = 0;
    while (b4 < 2) : (b4 += 1) {
        var j: u32 = 9;
        post4 += j;
        j += 1;
    }
    if (cap2 != 4 or cap3 != 4 or post4 != 18) {
        @panic("two-captures guard failed");
    }

    // --- bare-block `var j` at a shallower depth (t11) ----------------------
    var post5: u32 = 0;
    {
        var j: u32 = 10;
        post5 += j;
        j += 1;
        post5 += j;
    }
    if (post5 != 21) {
        @panic("bare-block var guard failed");
    }

    // --- controls -----------------------------------------------------------
    var ctl1: u32 = 0;
    for (0..3) |x| {
        for (0..2) |y| {
            _ = y;
        }
        if (x == 1) {
            ctl1 += 1;
        }
    }
    if (ctl1 != 1) {
        @panic("capture-after-nested-loop control failed");
    }

    var ctl2: u32 = 0;
    var b10: u32 = 0;
    while (b10 < 2) : (b10 += 1) {
        var k: u32 = 9;
        ctl2 += k;
        k += 1;
    }
    if (ctl2 != 18) {
        @panic("different-name control failed");
    }

    var ctl3: u32 = 0;
    for (0..3) |z| {
        if (z == 1) {
            ctl3 += 5;
        }
    }
    if (ctl3 != 5) {
        @panic("no-earlier-name control failed");
    }

    var ctl4: u32 = 0;
    var b6: u32 = 0;
    while (b6 < 2) : (b6 += 1) {
        {
            var j: u32 = 9;
            j += 1;
            ctl4 += j;
        }
    }
    if (ctl4 != 20) {
        @panic("same-depth nested-block control failed");
    }

    var wc: u32 = 0;
    var c: u32 = 0;
    while (c < 3) : (c += 1) {
        while (pick(c)) |j| {
            wc += j;
            break;
        }
    }
    if (wc != 5) {
        @panic("while-capture control failed");
    }

    var ic: u32 = 0;
    var c2: u32 = 0;
    while (c2 < 2) : (c2 += 1) {
        if (pick(c2)) |j| {
            ic += j;
        }
    }
    if (ic != 2) {
        @panic("if-capture control failed");
    }

    if (xfn_a() != 10 or xfn_b() != 8) {
        @panic("cross-function control failed");
    }

    std.io.print("c7={} g7={} s1b={} cap1={} post1={} post2={} post3={} cap2={} cap3={} post4={} post5={} ctl1={} ctl2={} ctl3={} ctl4={} wc={} ic={} xa={} xb={}\n", .{ c7, g7, s1b, cap1, post1, post2, post3, cap2, cap3, post4, post5, ctl1, ctl2, ctl3, ctl4, wc, ic, xfn_a(), xfn_b() });
}
