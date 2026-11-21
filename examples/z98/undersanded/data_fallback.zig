// data_fallback.zig — UNDERSANDED data.z98 zero-row helpers, table clear and
// compiled-in T1 fallback builder (spec §25.10).
//
// buildFallback is used by tests, the M6 tier, and tool paths that must run
// without data.z98 beside the exe. clearTables and the zero-row helpers are
// shared with the schema parser so both paths build identical images.

const def = @import("def.zig");
const creatures = @import("creatures_t1.zig");
const tables_t1 = @import("tables_t1.zig");

const ZERO_NAME = [def.MAX_NAME_LEN]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};

pub fn zeroDef() def.CreatureDef {
    return def.CreatureDef{
        .id = 0,
        .name = ZERO_NAME,
        .name_len = 0,
        .family = 0,
        .role = 0,
        .zone_mask = 0,
        .phase_mask = 0,
        .hp = 0,
        .resolve = 0,
        .speed = 0,
        .attack = 0,
        .thrash_regen = 0,
        .despair_regen = 0,
        .armor_pct = 100,
        .flags = 0,
        .resist_restrain_pct = 100,
        .blind_chance = 0,
        .subdue_chance = 95,
        .discharge_stat = 0,
        .discharge_th = 0,
        .discharge_dmg = 0,
        .armor_below_th = 0,
        .armor_below_pct = 0,
        .speed_below_stat = 0,
        .speed_below_th = 0,
        .speed_below_add = 0,
        .atk_below_th = 0,
        .atk_below_pct = 0,
        .flee_kind = 0,
        .flee_th = 0,
        .grudge_family = 0,
        .grudge_kind = 0,
        .grudge_value = 0,
        .sub = [def.MAX_DROP_LINES]def.DropLine{
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
        },
        .kill = [def.MAX_DROP_LINES]def.DropLine{
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
        },
        .over = [def.MAX_DROP_LINES]def.DropLine{
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
        },
        .sale = 0,
        .respawn = [3]i32{ 0, 0, 0 },
        .counter_tool = 0,
        .rule_start = 0,
        .rule_count = 0,
    };
}

pub fn zeroRule() def.Rule {
    return def.Rule{
        .cond_op = 0,
        .cond_a = 0,
        .cond_b = 0,
        .effect_op = 0,
        .effect_a = 0,
        .effect_b = 0,
        .timing = 0,
    };
}

pub fn zeroCost() def.CostSlot {
    return def.CostSlot{ .kind = 0, .amt = 0 };
}

pub fn zeroTool() def.ToolRow {
    return def.ToolRow{
        .id = 0,
        .kind = 0,
        .cost = [3]def.CostSlot{ zeroCost(), zeroCost(), zeroCost() },
    };
}

pub fn zeroUpgrade() def.UpgradeRow {
    return def.UpgradeRow{
        .axis = 0,
        .tier = 0,
        .cost = [3]def.CostSlot{ zeroCost(), zeroCost(), zeroCost() },
    };
}

pub fn zeroEncounter() def.EncounterRow {
    return def.EncounterRow{ .def_index = 0, .weight = 0 };
}

pub fn clearTables(t: *def.Tables) void {
    t.def_count = 0;
    t.rule_count = 0;
    t.tool_count = 0;
    t.upgrade_count = 0;
    t.cosmetic_count = 0;
    t.text_count = 0;
    t.content_version = 0;
    t.loaded = 0;

    var i: usize = 0;
    while (i < def.MAX_CREATURES) : (i += 1) {
        t.defs[i] = zeroDef();
    }
    i = 0;
    while (i < def.MAX_RULES) : (i += 1) {
        t.rules[i] = zeroRule();
    }
    i = 0;
    while (i < def.MAX_TOOLS) : (i += 1) {
        t.tools[i] = zeroTool();
    }
    i = 0;
    while (i < 15) : (i += 1) {
        t.upgrades[i] = zeroUpgrade();
    }
    i = 0;
    while (i < def.MAX_COSMETICS) : (i += 1) {
        t.cosmetics[i] = def.CosmeticRow{ .name = "", .price = 0, .unlock = 0 };
    }
    i = 0;
    while (i < def.MAX_ZONES * 2 * def.MAX_ENCOUNTER) : (i += 1) {
        t.encounters[i] = zeroEncounter();
    }
    i = 0;
    while (i < def.MAX_ZONES * 2) : (i += 1) {
        t.enc_count[i] = 0;
    }
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        t.zone_cost[i] = 0;
        t.zone_boss[i] = 0;
    }
    i = 0;
    while (i < def.MAX_TEXT_KEYS) : (i += 1) {
        t.text_key[i] = "";
        t.text_val[i] = "";
    }
}

// Compiled-in T1 fallback in a Tables image. Used by tests, the M6 tier, and
// the tool paths that must run without data.z98 beside the exe.
pub fn buildFallback(out: *def.Tables) void {
    clearTables(out);
    out.content_version = 2;
    out.loaded = 0;

    var i: usize = 0;
    while (i < creatures.DEFS.len) : (i += 1) {
        out.defs[i] = creatures.DEFS[i];
    }
    out.def_count = @intCast(i32, creatures.DEFS.len);

    i = 0;
    while (i < creatures.RULES.len) : (i += 1) {
        out.rules[i] = creatures.RULES[i];
    }
    out.rule_count = @intCast(i32, creatures.RULES.len);

    i = 0;
    while (i < tables_t1.TOOLS.len) : (i += 1) {
        out.tools[i] = tables_t1.TOOLS[i];
    }
    out.tool_count = @intCast(i32, tables_t1.TOOLS.len);

    i = 0;
    while (i < tables_t1.UPGRADES.len) : (i += 1) {
        out.upgrades[i] = tables_t1.UPGRADES[i];
    }
    out.upgrade_count = @intCast(i32, tables_t1.UPGRADES.len);

    i = 0;
    while (i < tables_t1.COSMETICS.len) : (i += 1) {
        out.cosmetics[i] = tables_t1.COSMETICS[i];
    }
    out.cosmetic_count = @intCast(i32, tables_t1.COSMETICS.len);

    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        out.zone_cost[i] = tables_t1.ZONE_COST[i];
        out.zone_boss[i] = tables_t1.ZONE_IS_BOSS[i];
    }

    var z: i32 = 0;
    while (z < @intCast(i32, def.MAX_ZONES)) : (z += 1) {
        var ph: i32 = 0;
        while (ph < 2) : (ph += 1) {
            const r = tables_t1.fallbackRows(z, ph);
            const ci: usize = @intCast(usize, z) * 2 + @intCast(usize, ph);
            const base: usize = @intCast(usize, z) * 2 * def.MAX_ENCOUNTER +
                @intCast(usize, ph) * def.MAX_ENCOUNTER;
            var j: usize = 0;
            while (j < r.len) : (j += 1) {
                out.encounters[base + j] = r[j];
            }
            out.enc_count[ci] = @intCast(i32, r.len);
        }
    }
}
