// def.zig — UNDERSANDED M2 flat definitions (spec §25.1–§25.3).
//
// Capacities are full-game from M1 and must never be resized (R14). All state
// is flat: no tagged-union payload stores (R1), no i64/u64/f64 fields (R10).

// ---- §25.1 Capacities -----------------------------------------------------

pub const MAX_CREATURES: usize = 56;
pub const MAX_ZONES: usize = 12;
pub const MAX_DROP_LINES: usize = 4;
pub const MAX_TOOLS: usize = 8;
pub const MAX_PARTS: usize = 14;
pub const MAX_MATERIALS: usize = 10;
pub const MAX_RULES: usize = 96;
pub const MAX_ENCOUNTER: usize = 24;
pub const MAX_LOG: usize = 64;
pub const MAX_COSMETICS: usize = 12;
pub const SUBDUE_PROMPT_BELOW: i32 = 90;

// ---- §25.2 Static definition ---------------------------------------------

pub const DropLine = struct { part: i32, count: i32 };

pub const CreatureDef = struct {
    id: i32, family: i32, role: i32,
    zone_mask: u32, phase_mask: u32,
    hp: i32, resolve: i32, speed: i32, attack: i32,
    thrash_regen: i32, despair_regen: i32,
    armor_pct: i32, flags: u32,
    resist_restrain_pct: i32,
    blind_chance: i32,
    subdue_chance: i32,
    discharge_stat: i32, discharge_th: i32, discharge_dmg: i32,
    armor_below_th: i32, armor_below_pct: i32,
    speed_below_stat: i32, speed_below_th: i32, speed_below_add: i32,
    atk_below_th: i32, atk_below_pct: i32,
    flee_kind: i32, flee_th: i32,
    grudge_family: i32, grudge_kind: i32, grudge_value: i32,
    sub: [MAX_DROP_LINES]DropLine,
    kill: [MAX_DROP_LINES]DropLine,
    over: [MAX_DROP_LINES]DropLine,
    sale: i32, respawn: [3]i32, counter_tool: i32,
    rule_start: i32, rule_count: i32,
};

// ---- §25.3 Fight state ----------------------------------------------------

pub const FightState = struct {
    def_index: i32,
    hp: i32, max_hp: i32, res: i32, max_res: i32,
    hull: i32, max_hull: i32,
    player_speed: i32, margin_pct: i32,
    round: i32, actions: i32, outcome: i32, flags: u32,
    prev_hp: i32, prev_res: i32,
    subdue_declined: i32, surge_count: i32, surge_atk_applied: i32,
    tool: i32, tool_charge: i32, tool_broken: i32, tool_active: i32,
    phase_state: i32, boss_phase: i32, boss_axis: i32,
    last_bar: i32, switches: i32, hull_spent: i32,
    rng_state: u32,
    rule_consumed: u32,
    pending_blind: i32, pending_ink: i32, pending_flee: i32,
    active_armor_pct: i32, active_resist_restrain: i32,
    cond: i32,
};

pub const World = struct {
    cycle: i32, phase: i32,
    ready: [MAX_ZONES * MAX_CREATURES]i32,
    seen_mask: [2]u32,
    journal_mask: [2]u32,
    tooltip_shown: u32,
    field_phases: i32,
    release_bonus: [MAX_ZONES]i32,
    lockout_until: [MAX_ZONES]i32,
    family_overkill_mask: u32, wary_mask: [2]u32,
    rng_state: u32,
    boat: [5]i32, money: i32,
    expertise: [MAX_MATERIALS]i32,
    cosmetics_owned: u32, cosmetics_unlocked: u32,
    field_record_written: i32,
    boss_variants_seen: u32, boss_kills: i32,
};

pub const LogEntry = struct { class: i32, msg_id: i32, a: i32, b: i32 };

pub const Expedition = struct {
    active: i32, zone: i32, fight_index: i32, seed: u32,
    hold: [MAX_PARTS]i32, hold_n: i32,
};

pub const Effect = struct { op: i32, a: i32, b: i32 };

pub const GameState = struct {
    fight: FightState,
    world: World,
    log: [MAX_LOG]LogEntry,
    log_n: i32,
    exp: Expedition,
    pending_cond: i32,
    screen: i32,
};

// ---- Action / outcome / bar / flag vocabulary ----------------------------

pub const ACT_STRIKE: i32 = 1;
pub const ACT_RESTRAIN: i32 = 2;
pub const ACT_EQUIP: i32 = 3;
pub const ACT_FLEE: i32 = 4;
pub const ACT_ATTEMPT: i32 = 5;
pub const ACT_DECLINE: i32 = 6;

pub const Action = struct { kind: i32, arg: i32 };

pub const OUT_ONGOING: i32 = 0;
pub const OUT_SUBDUE: i32 = 1;
pub const OUT_KILL: i32 = 2;
pub const OUT_OVERKILL: i32 = 3;
pub const OUT_CREATURE_FLED: i32 = 4;
pub const OUT_PLAYER_FLED: i32 = 5;

pub const BAR_NONE: i32 = 0;
pub const BAR_STRIKE: i32 = 1;
pub const BAR_RESTRAIN: i32 = 2;

pub const LOG_NORMAL: i32 = 0;
pub const LOG_WARN: i32 = 1;

pub const COND_NONE: i32 = 0;
pub const COND_DROWSY: i32 = 1;
pub const COND_SHAKY: i32 = 2;
pub const COND_EXPOSED: i32 = 3;

pub const F_BOSS: u32 = 1;
pub const F_STATIONARY: u32 = 2;
pub const F_SHELL: u32 = 4;
pub const F_PHASING: u32 = 8;
pub const F_DECOY: u32 = 16;
pub const F_INK: u32 = 32;
pub const F_GRUDGE_ARMOR: u32 = 64;

// Coupling regen default; a creature row value replaces it (never adds).
pub const COUPLING_REGEN_DEFAULT: i32 = 5;

// ---- Message table --------------------------------------------------------
//
// Log entries store a msg_id and render through this table (spec §25.3).
// The Last Surge flavor line is the one §40-authored row for M2.

pub const MSG_LAST_SURGE: i32 = 1;
// Decline copy used when no coupling regen is active (fight.MSG_DECLINE keeps
// the active-regen wording). Next free id after fight.zig's MSG_* table.
pub const MSG_DECLINE_PLAIN: i32 = 15;

pub const MsgRow = struct { id: i32, text: []const u8 };

pub const MESSAGES = [_]MsgRow{
    MsgRow{
        .id = MSG_LAST_SURGE,
        .text = "Its will returns in a slow, deliberate wave.",
    },
};

pub fn messageText(id: i32) ?[]const u8 {
    var i: usize = 0;
    while (i < MESSAGES.len) : (i += 1) {
        if (MESSAGES[i].id == id) return MESSAGES[i].text;
    }
    return null;
}
