// creatures_t1.zig — M2 hardcoded creature rows (spec §14.2–§14.3).
//
// The Task 3 fight resolver needs a data source for `startFight`; this is the
// provisional M2 table (five rows). All fields are explicit (R8) and every
// numeric literal mirrors spec §14.2/§14.3. Task 4 consumes/extends this table
// for the text fight screen.

const def = @import("def.zig");
const behavior = @import("behavior.zig");

// Role vocabulary used by this table.
pub const ROLE_COMMON: i32 = 1;
pub const ROLE_RARE: i32 = 3;

// `speed_below_stat` / `discharge_stat` vocabulary (fight.zig consumes these).
pub const STAT_HP: i32 = 1;
pub const STAT_RES: i32 = 2;

fn blank() def.CreatureDef {
    return def.CreatureDef{
        .id = 0,
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
        },
        .kill = [def.MAX_DROP_LINES]def.DropLine{
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
        },
        .sale = 0,
        .respawn = [3]i32{ 0, 0, 0 },
        .counter_tool = 0,
        .rule_start = 0,
        .rule_count = 0,
    };
}

// Row 1 — Mystic Eel (70/80/10/6, subdue 95, Despair override +8).
fn mysticEel() def.CreatureDef {
    var d = blank();
    d.id = 1;
    d.family = 1;
    d.role = ROLE_COMMON;
    d.hp = 70;
    d.resolve = 80;
    d.speed = 10;
    d.attack = 6;
    d.despair_regen = 8;
    d.subdue_chance = 95;
    d.sale = 20;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    return d;
}

// Row 2 — Mystic Electric Eel (80/100/16/7, subdue 95, Thrash +8,
// Discharge 8 Hull when Resolve crosses below 50%).
fn mysticElectricEel() def.CreatureDef {
    var d = blank();
    d.id = 2;
    d.family = 1;
    d.role = ROLE_COMMON;
    d.hp = 80;
    d.resolve = 100;
    d.speed = 16;
    d.attack = 7;
    d.thrash_regen = 8;
    d.subdue_chance = 95;
    d.discharge_stat = STAT_RES;
    d.discharge_th = 50;
    d.discharge_dmg = 8;
    d.sale = 30;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    d.rule_start = 0;
    d.rule_count = 1;
    return d;
}

// Row 4 — Steel Tuna (120/70/6/8, subdue 95, Armor Strike 60%,
// HP<30% -> Speed +4).
fn steelTuna() def.CreatureDef {
    var d = blank();
    d.id = 4;
    d.family = 2;
    d.role = ROLE_COMMON;
    d.hp = 120;
    d.resolve = 70;
    d.speed = 6;
    d.attack = 8;
    d.armor_pct = 60;
    d.subdue_chance = 95;
    d.speed_below_stat = STAT_HP;
    d.speed_below_th = 30;
    d.speed_below_add = 4;
    d.sale = 20;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    return d;
}

// Row 18 — Anemoniacus (95/115/7/9, rare subdue 60, Thrash +10,
// Discharge 10 Hull when HP crosses below 50%).
fn anemoniacus() def.CreatureDef {
    var d = blank();
    d.id = 18;
    d.family = 10;
    d.role = ROLE_RARE;
    d.hp = 95;
    d.resolve = 115;
    d.speed = 7;
    d.attack = 9;
    d.thrash_regen = 10;
    d.subdue_chance = 60;
    d.discharge_stat = STAT_HP;
    d.discharge_th = 48;
    d.discharge_dmg = 10;
    d.sale = 50;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.rule_start = 1;
    d.rule_count = 1;
    return d;
}

// Row 19 — Freezing Perch (105/95/13/10, rare subdue 60, Despair +8,
// flees next turn if a single hit deals >35% max HP (37)).
fn freezingPerch() def.CreatureDef {
    var d = blank();
    d.id = 19;
    d.family = 11;
    d.role = ROLE_RARE;
    d.hp = 105;
    d.resolve = 95;
    d.speed = 13;
    d.attack = 10;
    d.despair_regen = 8;
    d.subdue_chance = 60;
    d.flee_kind = 1;
    d.flee_th = 35;
    d.sale = 55;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    return d;
}

// Single source of truth for the five M2 rows (plan Task 4 interface).
pub const DEFS = [5]def.CreatureDef{
    mysticEel(),
    mysticElectricEel(),
    steelTuna(),
    anemoniacus(),
    freezingPerch(),
};

pub fn defAt(index: i32) def.CreatureDef {
    switch (index) {
        0 => return DEFS[0],
        1 => return DEFS[1],
        2 => return DEFS[2],
        3 => return DEFS[3],
        4 => return DEFS[4],
        else => return DEFS[0],
    }
}

// Rule rows (indexes match each def's rule_start/rule_count).
pub const RULES = [_]behavior.Rule{
    behavior.Rule{
        .cond_op = behavior.RES_BELOW,
        .cond_a = 50,
        .cond_b = 0,
        .effect_op = behavior.HULL_DMG,
        .effect_a = 8,
        .effect_b = 0,
        .timing = behavior.TIMING_ONESHOT,
    },
    behavior.Rule{
        .cond_op = behavior.HP_BELOW,
        .cond_a = 48,
        .cond_b = 0,
        .effect_op = behavior.HULL_DMG,
        .effect_a = 10,
        .effect_b = 0,
        .timing = behavior.TIMING_ONESHOT,
    },
};
