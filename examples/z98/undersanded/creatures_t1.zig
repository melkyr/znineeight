// creatures_t1.zig — hardcoded T1 creature rows (spec §14.2–§14.4).
//
// The fight resolver reads this table by dense index. Indices 0..4 are the
// original M2 rows (M3's token table and its tests depend on them); M4 appends
// rows 5..17, the 13 missing non-boss T1 creatures. All fields are explicit
// (R8) and every numeric literal mirrors spec §14.2/§14.3/§14.4.

const def = @import("def.zig");
const behavior = @import("behavior.zig");

// Role vocabulary used by this table.
pub const ROLE_COMMON: i32 = 1;
pub const ROLE_NAMED: i32 = 2;
pub const ROLE_RARE: i32 = 3;

// `speed_below_stat` / `discharge_stat` vocabulary (fight.zig consumes these).
pub const STAT_HP: i32 = 1;
pub const STAT_RES: i32 = 2;

// Family ids. Eel/Tuna are shared with the named grudges (§10); the remaining
// ids group the T1 families (Anemone/Perch keep their M2 ids 10/11).
pub const FAMILY_EEL: i32 = 1;
pub const FAMILY_TUNA: i32 = 2;
pub const FAMILY_CRAB: i32 = 3;
pub const FAMILY_JELLY: i32 = 4;
pub const FAMILY_BARNACLE: i32 = 5;
pub const FAMILY_RAY: i32 = 7;
pub const FAMILY_SQUID: i32 = 8;
pub const FAMILY_ANGLER: i32 = 9;
pub const FAMILY_ANEMONE: i32 = 10;
pub const FAMILY_PERCH: i32 = 11;
pub const FAMILY_WRASSE: i32 = 12;

// Grudge vocabulary (§10; applied from M5).
pub const GRUDGE_RES: i32 = 1;
pub const GRUDGE_ARMOR: i32 = 2;

// Part ids in spec §14.1 order (M5 refines these).
pub const PART_SHELL_CHIP: i32 = 1;
pub const PART_PLATE_SCRAP: i32 = 2;
pub const PART_GLAND_SAC: i32 = 3;
pub const PART_BRINE_VIAL: i32 = 4;
pub const PART_CORAL_BUD: i32 = 5;
pub const PART_GLOW_POLYP: i32 = 6;
pub const PART_GLASS_PANE: i32 = 7;
pub const PART_HOOKED_BARBEL: i32 = 8;
pub const PART_STEEL_FINS: i32 = 9;

// Counter-tool ids (§14.5). Plate=1 and Brine Net=2 match fight.TOOL_*; the
// rest are reserved for M5/M8 wiring and are inert here.
pub const TOOL_PLATE: i32 = 1;
pub const TOOL_BRINE_NET: i32 = 2;
pub const TOOL_ELECTRIC_GLAND: i32 = 3;
pub const TOOL_LURE: i32 = 4;
pub const TOOL_PRESSURE_HOOK: i32 = 5;
pub const TOOL_SONAR: i32 = 6;
pub const TOOL_CORAL_SHIELD: i32 = 7;

fn drop(part: i32, count: i32) def.DropLine {
    return def.DropLine{ .part = part, .count = count };
}

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

// Row 18 — Anemoniacus (95/80/7/9, rare subdue 65, Thrash +10,
// Discharge 10 Hull when HP crosses below 50%).
fn anemoniacus() def.CreatureDef {
    var d = blank();
    d.id = 18;
    d.family = 10;
    d.role = ROLE_RARE;
    d.hp = 95;
    d.resolve = 80;
    d.speed = 7;
    d.attack = 9;
    d.thrash_regen = 10;
    d.subdue_chance = 65;
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

// Row 19 — Freezing Perch (105/95/13/10, rare subdue 65, Despair +8,
// flees next turn if a single hit deals >20% max HP (21)).
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
    d.subdue_chance = 65;
    d.flee_kind = 1;
    d.flee_th = 20;
    d.sale = 55;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    return d;
}

// ---- M4 T1 rows (dense indices 5..17, roster ids per spec §14.2) ----------

// Roster 5 — Rust Tuna (80/60/8/7, Armor 80%, HP<30% flees next turn).
fn rustTuna() def.CreatureDef {
    var d = blank();
    d.id = 5;
    d.family = FAMILY_TUNA;
    d.role = ROLE_COMMON;
    d.hp = 80;
    d.resolve = 60;
    d.speed = 8;
    d.attack = 7;
    d.armor_pct = 80;
    d.subdue_chance = 95;
    d.sale = 15;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    d.counter_tool = TOOL_PRESSURE_HOOK;
    d.sub[0] = drop(PART_PLATE_SCRAP, 2);
    d.sub[1] = drop(PART_SHELL_CHIP, 2);
    d.kill[0] = drop(PART_SHELL_CHIP, 2);
    d.over[0] = drop(PART_SHELL_CHIP, 1);
    d.rule_start = 2;
    d.rule_count = 1;
    return d;
}

// Roster 7 — Kelp Crab (100/90/8/7, Thrash +6).
fn kelpCrab() def.CreatureDef {
    var d = blank();
    d.id = 7;
    d.family = FAMILY_CRAB;
    d.role = ROLE_COMMON;
    d.hp = 100;
    d.resolve = 90;
    d.speed = 8;
    d.attack = 7;
    d.thrash_regen = 6;
    d.subdue_chance = 95;
    d.sale = 20;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    d.counter_tool = TOOL_BRINE_NET;
    d.sub[0] = drop(PART_CORAL_BUD, 2);
    d.sub[1] = drop(PART_SHELL_CHIP, 2);
    d.kill[0] = drop(PART_CORAL_BUD, 1);
    d.kill[1] = drop(PART_SHELL_CHIP, 1);
    d.over[0] = drop(PART_SHELL_CHIP, 1);
    return d;
}

// Roster 8 — Brine Jelly (60/110/10/6, Despair +10).
fn brineJelly() def.CreatureDef {
    var d = blank();
    d.id = 8;
    d.family = FAMILY_JELLY;
    d.role = ROLE_COMMON;
    d.hp = 60;
    d.resolve = 110;
    d.speed = 10;
    d.attack = 6;
    d.despair_regen = 10;
    d.subdue_chance = 95;
    d.sale = 20;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    d.counter_tool = TOOL_ELECTRIC_GLAND;
    d.sub[0] = drop(PART_BRINE_VIAL, 3);
    d.sub[1] = drop(PART_SHELL_CHIP, 1);
    d.kill[0] = drop(PART_BRINE_VIAL, 1);
    d.kill[1] = drop(PART_SHELL_CHIP, 1);
    d.over[0] = drop(PART_BRINE_VIAL, 1);
    return d;
}

// Roster 9 — Chitin Barnacle (130/50/3/6, HP<50% -> Armor 70%, Stationary).
fn chitinBarnacle() def.CreatureDef {
    var d = blank();
    d.id = 9;
    d.family = FAMILY_BARNACLE;
    d.role = ROLE_COMMON;
    d.hp = 130;
    d.resolve = 50;
    d.speed = 3;
    d.attack = 6;
    d.armor_below_th = 50;
    d.armor_below_pct = 70;
    d.flags = def.F_STATIONARY;
    d.subdue_chance = 95;
    d.sale = 15;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    d.counter_tool = TOOL_PLATE;
    d.sub[0] = drop(PART_SHELL_CHIP, 4);
    d.sub[1] = drop(PART_CORAL_BUD, 1);
    d.kill[0] = drop(PART_SHELL_CHIP, 2);
    d.over[0] = drop(PART_SHELL_CHIP, 1);
    return d;
}

// Roster 10 — Spark Anemone (90/70/4/6, Discharge 10 Hull at HP<50%,
// Stationary).
fn sparkAnemone() def.CreatureDef {
    var d = blank();
    d.id = 10;
    d.family = FAMILY_ANEMONE;
    d.role = ROLE_COMMON;
    d.hp = 90;
    d.resolve = 70;
    d.speed = 4;
    d.attack = 6;
    d.flags = def.F_STATIONARY;
    d.subdue_chance = 95;
    d.discharge_stat = STAT_HP;
    d.discharge_th = 45;
    d.discharge_dmg = 10;
    d.sale = 20;
    d.respawn[0] = 3;
    d.respawn[1] = 9;
    d.respawn[2] = 15;
    d.counter_tool = TOOL_CORAL_SHIELD;
    d.rule_start = 3;
    d.rule_count = 1;
    d.sub[0] = drop(PART_GLAND_SAC, 2);
    d.sub[1] = drop(PART_SHELL_CHIP, 1);
    d.kill[0] = drop(PART_GLAND_SAC, 1);
    d.kill[1] = drop(PART_SHELL_CHIP, 1);
    d.over[0] = drop(PART_GLAND_SAC, 1);
    return d;
}

// Roster 3 — Mileel (80/140/12/8, named, Despair +10, flees if a hit exceeds
// 30% max HP, grudge +30 Resolve).
fn mileel() def.CreatureDef {
    var d = blank();
    d.id = 3;
    d.family = FAMILY_EEL;
    d.role = ROLE_NAMED;
    d.hp = 80;
    d.resolve = 140;
    d.speed = 12;
    d.attack = 8;
    d.despair_regen = 10;
    d.subdue_chance = 80;
    d.flee_kind = 1;
    d.flee_th = 30;
    d.grudge_family = FAMILY_EEL;
    d.grudge_kind = GRUDGE_RES;
    d.grudge_value = 30;
    d.sale = 40;
    d.respawn[0] = 4;
    d.respawn[1] = 12;
    d.respawn[2] = 20;
    d.counter_tool = TOOL_PRESSURE_HOOK;
    d.sub[0] = drop(PART_GLAND_SAC, 4);
    d.sub[1] = drop(PART_SHELL_CHIP, 2);
    d.sub[2] = drop(PART_HOOKED_BARBEL, 1);
    d.kill[0] = drop(PART_GLAND_SAC, 2);
    d.kill[1] = drop(PART_SHELL_CHIP, 1);
    d.over[0] = drop(PART_GLAND_SAC, 1);
    return d;
}

// Roster 6 — Tunisteel (140/100/5/9, named, Heavy Armor 50%, HP<30% -> Speed
// +6, grudge armor 50% -> 30%).
fn tunisteel() def.CreatureDef {
    var d = blank();
    d.id = 6;
    d.family = FAMILY_TUNA;
    d.role = ROLE_NAMED;
    d.hp = 140;
    d.resolve = 100;
    d.speed = 5;
    d.attack = 9;
    d.armor_pct = 50;
    d.subdue_chance = 80;
    d.speed_below_stat = STAT_HP;
    d.speed_below_th = 30;
    d.speed_below_add = 6;
    d.grudge_family = FAMILY_TUNA;
    d.grudge_kind = GRUDGE_ARMOR;
    d.grudge_value = 30;
    d.sale = 40;
    d.respawn[0] = 4;
    d.respawn[1] = 12;
    d.respawn[2] = 20;
    d.counter_tool = TOOL_PLATE;
    d.sub[0] = drop(PART_PLATE_SCRAP, 4);
    d.sub[1] = drop(PART_SHELL_CHIP, 2);
    d.sub[2] = drop(PART_STEEL_FINS, 2);
    d.kill[0] = drop(PART_PLATE_SCRAP, 2);
    d.kill[1] = drop(PART_SHELL_CHIP, 1);
    d.over[0] = drop(PART_PLATE_SCRAP, 1);
    return d;
}

// Roster 11 — Coral Crab (160/120/5/10, Shell: Restrain 50%, Thrash +12).
fn coralCrab() def.CreatureDef {
    var d = blank();
    d.id = 11;
    d.family = FAMILY_CRAB;
    d.role = ROLE_RARE;
    d.hp = 160;
    d.resolve = 120;
    d.speed = 5;
    d.attack = 10;
    d.thrash_regen = 12;
    d.flags = def.F_SHELL;
    d.resist_restrain_pct = 50;
    d.subdue_chance = 60;
    d.sale = 55;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.counter_tool = TOOL_BRINE_NET;
    d.sub[0] = drop(PART_CORAL_BUD, 3);
    d.sub[1] = drop(PART_SHELL_CHIP, 2);
    d.kill[0] = drop(PART_CORAL_BUD, 1);
    d.kill[1] = drop(PART_SHELL_CHIP, 1);
    d.over[0] = drop(PART_SHELL_CHIP, 1);
    return d;
}

// Roster 12 — Abyssal Lantern-Jelly (90/130/11/9, Resolve<50% -> blind 50%,
// Despair +12).
fn abyssalLanternJelly() def.CreatureDef {
    var d = blank();
    d.id = 12;
    d.family = FAMILY_JELLY;
    d.role = ROLE_RARE;
    d.hp = 90;
    d.resolve = 130;
    d.speed = 11;
    d.attack = 9;
    d.despair_regen = 12;
    d.blind_chance = 50;
    d.subdue_chance = 60;
    d.sale = 55;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.counter_tool = TOOL_LURE;
    d.sub[0] = drop(PART_GLOW_POLYP, 2);
    d.sub[1] = drop(PART_BRINE_VIAL, 3);
    d.kill[0] = drop(PART_GLOW_POLYP, 1);
    d.kill[1] = drop(PART_BRINE_VIAL, 1);
    d.over[0] = drop(PART_BRINE_VIAL, 1);
    return d;
}

// Roster 13 — Neon Ghost-Ray (100/110/18/10, Phasing every 2 rounds;
// HP<30% stays Phase).
fn neonGhostRay() def.CreatureDef {
    var d = blank();
    d.id = 13;
    d.family = FAMILY_RAY;
    d.role = ROLE_RARE;
    d.hp = 100;
    d.resolve = 110;
    d.speed = 18;
    d.attack = 10;
    d.flags = def.F_PHASING;
    d.subdue_chance = 60;
    d.sale = 60;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.counter_tool = TOOL_SONAR;
    d.sub[0] = drop(PART_GLOW_POLYP, 4);
    d.sub[1] = drop(PART_BRINE_VIAL, 2);
    d.kill[0] = drop(PART_GLOW_POLYP, 1);
    d.kill[1] = drop(PART_BRINE_VIAL, 1);
    d.over[0] = drop(PART_BRINE_VIAL, 1);
    return d;
}

// Roster 14 — Glass Squid (100/130/14/9, Ink every 3 rounds; Resolve<50% ->
// Speed +6).
fn glassSquid() def.CreatureDef {
    var d = blank();
    d.id = 14;
    d.family = FAMILY_SQUID;
    d.role = ROLE_RARE;
    d.hp = 100;
    d.resolve = 130;
    d.speed = 14;
    d.attack = 9;
    d.flags = def.F_INK;
    d.subdue_chance = 60;
    d.speed_below_stat = STAT_RES;
    d.speed_below_th = 50;
    d.speed_below_add = 6;
    d.sale = 65;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.counter_tool = TOOL_SONAR;
    d.sub[0] = drop(PART_GLASS_PANE, 4);
    d.sub[1] = drop(PART_BRINE_VIAL, 2);
    d.kill[0] = drop(PART_GLASS_PANE, 1);
    d.kill[1] = drop(PART_BRINE_VIAL, 1);
    d.over[0] = drop(PART_BRINE_VIAL, 1);
    return d;
}

// Roster 15 — Brine Angler (110/100/9/10, round 1 decoy; HP<50% -> Attack
// +50%).
fn brineAngler() def.CreatureDef {
    var d = blank();
    d.id = 15;
    d.family = FAMILY_ANGLER;
    d.role = ROLE_RARE;
    d.hp = 110;
    d.resolve = 100;
    d.speed = 9;
    d.attack = 10;
    d.flags = def.F_DECOY;
    d.subdue_chance = 60;
    d.atk_below_th = 50;
    d.atk_below_pct = 50;
    d.sale = 50;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.counter_tool = TOOL_LURE;
    d.sub[0] = drop(PART_GLOW_POLYP, 2);
    d.sub[1] = drop(PART_BRINE_VIAL, 2);
    d.kill[0] = drop(PART_GLOW_POLYP, 1);
    d.kill[1] = drop(PART_BRINE_VIAL, 1);
    d.over[0] = drop(PART_BRINE_VIAL, 1);
    return d;
}

// Roster 16 — Ironclad Wrasse (150/140/7/11, HP<30% -> Armor 50% + Speed +4).
fn ironcladWrasse() def.CreatureDef {
    var d = blank();
    d.id = 16;
    d.family = FAMILY_WRASSE;
    d.role = ROLE_RARE;
    d.hp = 150;
    d.resolve = 140;
    d.speed = 7;
    d.attack = 11;
    d.armor_below_th = 30;
    d.armor_below_pct = 50;
    d.subdue_chance = 60;
    d.speed_below_stat = STAT_HP;
    d.speed_below_th = 30;
    d.speed_below_add = 4;
    d.sale = 70;
    d.respawn[0] = 6;
    d.respawn[1] = 18;
    d.respawn[2] = 30;
    d.counter_tool = TOOL_PLATE;
    d.sub[0] = drop(PART_PLATE_SCRAP, 3);
    d.sub[1] = drop(PART_CORAL_BUD, 2);
    d.sub[2] = drop(PART_GLASS_PANE, 2);
    d.kill[0] = drop(PART_PLATE_SCRAP, 2);
    d.kill[1] = drop(PART_CORAL_BUD, 1);
    d.over[0] = drop(PART_PLATE_SCRAP, 1);
    return d;
}

// Single source of truth for the T1 rows. Indices 0..4 are the M2/M3 sim
// creatures and must not move (the token table and their tests depend on it);
// indices 5..17 are the 13 M4 rows in dense order.
pub const DEFS = [18]def.CreatureDef{
    mysticEel(),
    mysticElectricEel(),
    steelTuna(),
    anemoniacus(),
    freezingPerch(),
    rustTuna(),
    kelpCrab(),
    brineJelly(),
    chitinBarnacle(),
    sparkAnemone(),
    mileel(),
    tunisteel(),
    coralCrab(),
    abyssalLanternJelly(),
    neonGhostRay(),
    glassSquid(),
    brineAngler(),
    ironcladWrasse(),
};

pub fn defCount() i32 {
    return @intCast(i32, DEFS.len);
}

pub fn defAt(index: i32) def.CreatureDef {
    switch (index) {
        0 => return DEFS[0],
        1 => return DEFS[1],
        2 => return DEFS[2],
        3 => return DEFS[3],
        4 => return DEFS[4],
        5 => return DEFS[5],
        6 => return DEFS[6],
        7 => return DEFS[7],
        8 => return DEFS[8],
        9 => return DEFS[9],
        10 => return DEFS[10],
        11 => return DEFS[11],
        12 => return DEFS[12],
        13 => return DEFS[13],
        14 => return DEFS[14],
        15 => return DEFS[15],
        16 => return DEFS[16],
        17 => return DEFS[17],
        else => @panic("defAt: invalid creature index"),
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
    behavior.Rule{
        .cond_op = behavior.HP_BELOW,
        .cond_a = 24,
        .cond_b = 0,
        .effect_op = behavior.SET_FLEE,
        .effect_a = 1,
        .effect_b = 0,
        .timing = behavior.TIMING_ONESHOT,
    },
    behavior.Rule{
        .cond_op = behavior.HP_BELOW,
        .cond_a = 45,
        .cond_b = 0,
        .effect_op = behavior.HULL_DMG,
        .effect_a = 10,
        .effect_b = 0,
        .timing = behavior.TIMING_ONESHOT,
    },
};
