// core_test.zig — native Linux tests for M2 Task 1 definitions/math/rng.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/core_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/core_test"
//   "$OUT/core_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const math = @import("../math.zig");
const rng = @import("../rng.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn tCapacities() bool {
    if (def.MAX_CREATURES != 56) return false;
    if (def.MAX_ZONES != 12) return false;
    if (def.MAX_DROP_LINES != 4) return false;
    if (def.MAX_TOOLS != 8) return false;
    if (def.MAX_PARTS != 14) return false;
    if (def.MAX_MATERIALS != 10) return false;
    if (def.MAX_RULES != 96) return false;
    if (def.MAX_ENCOUNTER != 24) return false;
    if (def.MAX_LOG != 64) return false;
    if (def.MAX_COSMETICS != 12) return false;
    if (def.SUBDUE_PROMPT_BELOW != 90) return false;
    return true;
}

fn tFlags() bool {
    if (def.F_BOSS != 1) return false;
    if (def.F_STATIONARY != 2) return false;
    if (def.F_SHELL != 4) return false;
    if (def.F_PHASING != 8) return false;
    if (def.F_DECOY != 16) return false;
    if (def.F_INK != 32) return false;
    if (def.F_GRUDGE_ARMOR != 64) return false;
    if (def.COUPLING_REGEN_DEFAULT != 5) return false;
    return true;
}

fn tLastSurgeMessage() bool {
    const text = def.messageText(def.MSG_LAST_SURGE) orelse return false;
    if (!eq(text, "Its will returns in a slow, deliberate wave.")) return false;
    if (def.messageText(999) != null) return false;
    return true;
}

fn tApplyPct() bool {
    if (math.applyPct(25, 150) != 37) return false;
    if (math.applyPct(25, 60) != 15) return false;
    if (math.applyPct(33, 150) != 49) return false;
    if (math.applyPct(7, 150) != 10) return false;
    if (math.applyPct(100, 150) != 150) return false;
    if (math.applyPct(-25, 60) != -15) return false;
    if (math.applyPct(-1, 150) != -1) return false;
    return true;
}

fn ceilPct30Ref(max: i32) i32 {
    const scaled = max * 30;
    const q = scaled / 100;
    const r = scaled % 100;
    if (r == 0) return q;
    return q + 1;
}

fn tCeilPct30() bool {
    var max: i32 = 50;
    while (max <= 195) : (max += 1) {
        if (math.ceilPct(max, 30) != ceilPct30Ref(max)) return false;
    }
    if (math.ceilPct(50, 30) != 15) return false;
    if (math.ceilPct(195, 30) != 59) return false;
    return true;
}

// Raw xorshift32 values from seed 98 (no warm-up), golden.
fn tXorshiftRaw() bool {
    var s: u32 = 98;
    if (rng.rngNext(&s) != 25447652) return false;
    if (rng.rngNext(&s) != 2332661224) return false;
    if (rng.rngNext(&s) != 2402152306) return false;
    if (rng.rngNext(&s) != 1790276723) return false;
    if (rng.rngNext(&s) != 1129692078) return false;
    return true;
}

// Seeded stream after the 3× warm-up, golden.
fn tXorshiftSeeded() bool {
    var s: u32 = 0;
    rng.rngSeed(&s, 98);
    if (s != 2402152306) return false;
    if (rng.rngNext(&s) != 1790276723) return false;
    if (rng.rngNext(&s) != 1129692078) return false;
    if (rng.rngNext(&s) != 1881159294) return false;
    if (rng.rngNext(&s) != 2870373417) return false;
    if (rng.rngNext(&s) != 3036451680) return false;
    return true;
}

fn tRngRangeGolden() bool {
    var s: u32 = 0;
    rng.rngSeed(&s, 98);
    if (rng.rngRange(&s, 1, 100) != 24) return false;
    if (rng.rngRange(&s, 1, 100) != 79) return false;
    if (rng.rngRange(&s, 1, 100) != 95) return false;
    if (rng.rngRange(&s, 1, 100) != 18) return false;
    if (rng.rngRange(&s, 1, 100) != 81) return false;
    return true;
}

fn tWarmupApplied() bool {
    var raw: u32 = 98;
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        _ = rng.rngNext(&raw);
    }
    const raw_first = rng.rngNext(&raw);

    var seeded: u32 = 0;
    rng.rngSeed(&seeded, 98);
    const seeded_first = rng.rngNext(&seeded);

    if (raw_first != seeded_first) return false;

    var cold: u32 = 98;
    const cold_first = rng.rngNext(&cold);
    if (cold_first == seeded_first) return false;
    return true;
}

fn tRngDeterminism() bool {
    var a: u32 = 0;
    var b: u32 = 0;
    rng.rngSeed(&a, 98);
    rng.rngSeed(&b, 98);

    var i: i32 = 0;
    while (i < 64) : (i += 1) {
        if (rng.rngNext(&a) != rng.rngNext(&b)) return false;
    }

    var c: u32 = 0;
    rng.rngSeed(&c, 99);
    var d: u32 = 0;
    rng.rngSeed(&d, 99);
    i = 0;
    while (i < 64) : (i += 1) {
        if (rng.rngNext(&c) != rng.rngNext(&d)) return false;
    }

    if (a == c) return false;
    return true;
}

fn subdueSucceeds(roll: i32, chance: i32) bool {
    return roll <= chance;
}

fn tSubdueMapping() bool {
    if (!subdueSucceeds(1, 60)) return false;
    if (!subdueSucceeds(60, 60)) return false;
    if (subdueSucceeds(61, 60)) return false;
    if (subdueSucceeds(100, 60)) return false;

    var roll: i32 = 1;
    while (roll <= 100) : (roll += 1) {
        const want = roll <= 60;
        if (subdueSucceeds(roll, 60) != want) return false;
    }
    return true;
}

fn tZeroSeedReseed() bool {
    if (rng.ZERO_SEED != 0x9E3779B9) return false;

    var z: u32 = 0;
    if (rng.rngNext(&z) != 1359758873) return false;
    if (z == 0) return false;

    var a: u32 = 0;
    var b: u32 = 0;
    rng.rngSeed(&a, 0);
    rng.rngSeed(&b, rng.ZERO_SEED);

    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        if (rng.rngNext(&a) != rng.rngNext(&b)) return false;
    }
    return true;
}

pub fn main() void {
    report("capacities_frozen", tCapacities());
    report("flag_vocabulary", tFlags());
    report("last_surge_message_row", tLastSurgeMessage());
    report("apply_pct_truncation", tApplyPct());
    report("ceil_pct30_50_to_195", tCeilPct30());
    report("xorshift32_seed98_raw_golden", tXorshiftRaw());
    report("xorshift32_seed98_warmup_golden", tXorshiftSeeded());
    report("rng_range_seed98_golden", tRngRangeGolden());
    report("rng_warmup_applied", tWarmupApplied());
    report("rng_determinism", tRngDeterminism());
    report("subdue_mapping_chance60", tSubdueMapping());
    report("zero_seed_reseed", tZeroSeedReseed());

    if (fails != 0) os.exit(1);
    io.write("core_test PASS\n");
}
