// encounter.zig — UNDERSANDED encounter pipeline (spec §12).
//
// Build the available zone/phase pool, scale rare rows to `rareChance` and
// commons to the remainder with largest-remainder integer apportionment, then
// draw exactly one value from `World.rng_state`. Lockout is already folded into
// `world.rareChance`; this module never writes it.
//
// Flat state only (R1); module consts (R2); every switch has an else (R3);
// i32 arithmetic with bounded products (R6/R11).

const def = @import("def.zig");
const world = @import("world.zig");
const rng = @import("rng.zig");
const creatures = @import("creatures_t1.zig");
const tables = @import("tables_t1.zig");

pub const TOTAL_PCT: i32 = 100;
pub const PICK_MIN: i32 = 1;
pub const NO_ROW: i32 = -1;

const GROUP_COMMON: i32 = 0;
const GROUP_RARE: i32 = 1;

fn clampTarget(v: i32) i32 {
    if (v < 0) return 0;
    if (v > TOTAL_PCT) return TOTAL_PCT;
    return v;
}

fn isRare(index: i32) bool {
    return creatures.defAt(index).role == creatures.ROLE_RARE;
}

// Largest-remainder apportionment of one group (rare or common) onto `target`.
// `groups` tags each slot, `raws` holds its base weight, `out` receives the
// scaled weight. Slots outside `want` are left untouched.
fn apportionInto(groups: []const i32, raws: []const i32, n: i32, want: i32, target: i32, out: []i32) void {
    var total: i32 = 0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        if (groups[u] != want) continue;
        if (raws[u] > 0) total += raws[u];
    }

    i = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        if (groups[u] == want) out[u] = 0;
    }

    if (total <= 0 or target <= 0) return;

    var remainders: [def.MAX_ENCOUNTER]i32 = undefined;
    var awarded: [def.MAX_ENCOUNTER]i32 = undefined;
    i = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        remainders[u] = 0;
        awarded[u] = 0;
    }

    var used: i32 = 0;
    i = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        if (groups[u] != want) continue;
        if (raws[u] <= 0) continue;
        const scaled = target * raws[u];
        const q = scaled / total;
        out[u] = q;
        remainders[u] = scaled % total;
        used += q;
    }

    var left = target - used;
    while (left > 0) {
        var best: i32 = NO_ROW;
        var best_rem: i32 = -1;
        i = 0;
        while (i < n) : (i += 1) {
            const u: usize = @intCast(usize, i);
            if (groups[u] != want) continue;
            if (awarded[u] != 0) continue;
            if (remainders[u] > best_rem) {
                best_rem = remainders[u];
                best = i;
            }
        }
        if (best < 0) break;
        const bu: usize = @intCast(usize, best);
        out[bu] += 1;
        awarded[bu] = 1;
        left -= 1;
    }
}

// Build the final scaled pool for the world's current phase. Returns the row
// count, or NO_ROW when no species is available (safe Rest).
pub fn apportion(w: *def.World, zone: i32, out_def: *[def.MAX_ENCOUNTER]i32, out_weight: *[def.MAX_ENCOUNTER]i32) i32 {
    const pool = tables.rows(zone, w.phase);

    var avail_def: [def.MAX_ENCOUNTER]i32 = undefined;
    var avail_raw: [def.MAX_ENCOUNTER]i32 = undefined;
    var avail_group: [def.MAX_ENCOUNTER]i32 = undefined;
    var final_w: [def.MAX_ENCOUNTER]i32 = undefined;

    var i: usize = 0;
    while (i < def.MAX_ENCOUNTER) : (i += 1) {
        avail_def[i] = 0;
        avail_raw[i] = 0;
        avail_group[i] = 0;
        final_w[i] = 0;
    }

    var n: i32 = 0;
    i = 0;
    while (i < pool.len) : (i += 1) {
        if (n >= @intCast(i32, def.MAX_ENCOUNTER)) break;
        const row = pool[i];
        if (!world.available(w, zone, row.def_index)) continue;
        const u: usize = @intCast(usize, n);
        avail_def[u] = row.def_index;
        avail_raw[u] = row.weight;
        if (isRare(row.def_index)) {
            avail_group[u] = GROUP_RARE;
        } else {
            avail_group[u] = GROUP_COMMON;
        }
        n += 1;
    }

    if (n <= 0) return NO_ROW;

    var rare_n: i32 = 0;
    var common_n: i32 = 0;
    i = 0;
    while (i < @intCast(usize, n)) : (i += 1) {
        if (avail_group[i] == GROUP_RARE) {
            rare_n += 1;
        } else {
            common_n += 1;
        }
    }

    var rare_target: i32 = 0;
    var common_target: i32 = 0;
    if (rare_n > 0 and common_n > 0) {
        rare_target = clampTarget(world.rareChance(w, zone));
        common_target = TOTAL_PCT - rare_target;
    } else if (rare_n > 0) {
        rare_target = clampTarget(world.rareChance(w, zone));
    } else {
        common_target = TOTAL_PCT;
    }

    apportionInto(avail_group[0..], avail_raw[0..], n, GROUP_RARE, rare_target, final_w[0..]);
    apportionInto(avail_group[0..], avail_raw[0..], n, GROUP_COMMON, common_target, final_w[0..]);

    i = 0;
    while (i < @intCast(usize, n)) : (i += 1) {
        out_def[i] = avail_def[i];
        out_weight[i] = final_w[i];
    }
    return n;
}

// Count the species currently available in the node/phase pool. Pure read:
// no weights are apportioned and no RNG is drawn.
pub fn availableCount(w: *const def.World, zone: i32) i32 {
    const pool = tables.rows(zone, w.phase);
    var n: i32 = 0;
    var i: usize = 0;
    while (i < pool.len) : (i += 1) {
        if (world.available(w, zone, pool[i].def_index)) n += 1;
    }
    return n;
}

// Roll one encounter. False means the pool was empty (safe Rest).
pub fn rollEncounter(w: *def.World, zone: i32, out: *i32) bool {
    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;

    var i: usize = 0;
    while (i < def.MAX_ENCOUNTER) : (i += 1) {
        defs[i] = 0;
        weights[i] = 0;
    }

    const n = apportion(w, zone, &defs, &weights);
    if (n <= 0) return false;

    var total: i32 = 0;
    i = 0;
    while (i < @intCast(usize, n)) : (i += 1) {
        total += weights[i];
    }
    if (total <= 0) return false;

    // rngRange takes *u32; World.rng_state is u32, so no copy is needed.
    const roll = rng.rngRange(&w.rng_state, PICK_MIN, total);
    var acc: i32 = 0;
    var pick: i32 = NO_ROW;
    i = 0;
    while (i < @intCast(usize, n)) : (i += 1) {
        acc += weights[i];
        if (roll <= acc) {
            pick = @intCast(i32, i);
            break;
        }
    }
    if (pick < 0) return false;

    const chosen = defs[@intCast(usize, pick)];
    out.* = chosen;
    if (isRare(chosen)) world.clearReleaseBonus(w, zone);
    return true;
}
