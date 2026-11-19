// economy.zig — UNDERSANDED dock economy arithmetic (spec §11, §16, §17).
//
// Material ids follow R7: 1 Chitin, 2 Steel Plate, 3 Gland, 4 Brine, 5 Coral,
// 6 Luminescence, 7 Glass; 8/9 are the Hooked Barbel / Steel Fins keystone
// parts. `MaterialAmt.kind == 0` marks an unused cost slot.
//
// Upgrade costs are never restated here: `upgradeCost` reads `tables.UPGRADES`
// and converts each `CostSlot` into a `MaterialAmt` (R13). Module consts, all
// i32 arithmetic (R2/R6).

const tables = @import("tables_t1.zig");

pub const MAT_CHITIN: i32 = 1;
pub const MAT_PLATE: i32 = 2;
pub const MAT_GLAND: i32 = 3;
pub const MAT_BRINE: i32 = 4;
pub const MAT_CORAL: i32 = 5;
pub const MAT_LUM: i32 = 6;
pub const MAT_GLASS: i32 = 7;
pub const MAT_HOOKED_BARBEL: i32 = 8;
pub const MAT_STEEL_FINS: i32 = 9;

pub const MaterialAmt = struct { kind: i32, amt: i32 };

const NONE_AMT = MaterialAmt{ .kind = 0, .amt = 0 };

// Base refine yield for E0–E5; deep materials lose 1 below E5 (never clamped).
const BASE_YIELD = [6]i32{ 1, 2, 2, 3, 3, 3 };

// §17 upgrade totals by material id (index 0 unused).
const TARGETS = [8]i32{ 0, 19, 6, 21, 26, 26, 5, 8 };

const GATE_T2: i32 = 2;
const GATE_T3: i32 = 4;

pub fn isDeepMaterial(m: i32) bool {
    return m == MAT_LUM or m == MAT_GLASS;
}

pub fn refineYield(exp: i32, is_deep: bool) i32 {
    var idx = exp;
    if (idx < 0) idx = 0;
    if (idx > 5) idx = 5;
    var yield = BASE_YIELD[@intCast(usize, idx)];
    if (is_deep and exp < 5) yield -= 1;
    return yield;
}

// §17 total material target for one material id; 0 for non-materials.
pub fn targetTotal(m: i32) i32 {
    if (m < MAT_CHITIN or m > MAT_GLASS) return 0;
    return TARGETS[@intCast(usize, m)];
}

pub fn materialTotal(m: i32) i32 {
    return targetTotal(m);
}

// Look up the §11 cost row by axis/tier and convert its slots into `out`.
// The Z98 transpiler cannot return a C array by value, so this uses an
// out-parameter while preserving the planned `[3]MaterialAmt` shape.
pub fn upgradeCost(axis: i32, tier: i32, out: *[3]MaterialAmt) void {
    out[0] = NONE_AMT;
    out[1] = NONE_AMT;
    out[2] = NONE_AMT;

    const rows = tables.upgrades();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        const row = rows[i];
        if (row.axis != axis or row.tier != tier) continue;
        out[0] = MaterialAmt{ .kind = row.cost[0].kind, .amt = row.cost[0].amt };
        out[1] = MaterialAmt{ .kind = row.cost[1].kind, .amt = row.cost[1].amt };
        out[2] = MaterialAmt{ .kind = row.cost[2].kind, .amt = row.cost[2].amt };
        return;
    }
}

// T1 has no gate; T2 needs E2 in every material spent, T3 needs E4. Keystone
// parts (kinds 8/9) and unused slots (0) are not materials and are skipped.
pub fn canBuyTier(axis: i32, tier: i32, expertise: *const [10]i32, cost: [3]MaterialAmt) bool {
    _ = axis;
    if (tier <= 1) return true;
    var required = GATE_T3;
    if (tier == 2) required = GATE_T2;

    var i: usize = 0;
    while (i < cost.len) : (i += 1) {
        const kind = cost[i].kind;
        if (kind < MAT_CHITIN or kind > MAT_GLASS) continue;
        if (cost[i].amt <= 0) continue;
        const u: usize = @intCast(usize, kind);
        if (expertise[u] < required) return false;
    }
    return true;
}
