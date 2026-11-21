// def.zig — UNDERSANDED M2 flat definitions (spec §25.1–§25.3).
//
// Capacities are full-game from M1 and must never be resized (R14). All state
// is flat: no tagged-union payload stores (R1), no i64/u64/f64 fields (R10).

// ---- §25.1 Capacities -----------------------------------------------------

pub const MAX_CREATURES: usize = 56;
pub const MAX_ZONES: usize = 12;
pub const MAX_DROP_LINES: usize = 6;
pub const MAX_TOOLS: usize = 8;
pub const MAX_PARTS: usize = 14;
pub const MAX_MATERIALS: usize = 10;
pub const MAX_RULES: usize = 96;
pub const MAX_ENCOUNTER: usize = 24;
pub const MAX_LOG: usize = 64;
pub const MAX_COSMETICS: usize = 12;
pub const SUBDUE_PROMPT_BELOW: i32 = 90;
pub const MAX_NAME_LEN: usize = 24;
pub const MAX_TEXT_KEYS: usize = 256;
pub const MAX_TEXT_BYTES: usize = 48 * 1024;

// ---- §25.2 Static definition ---------------------------------------------

pub const DropLine = struct { part: i32, count: i32 };

pub const CreatureDef = struct {
    id: i32, name: [MAX_NAME_LEN]u8, name_len: i32,
    family: i32, role: i32,
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

// ---- §25.2 Content tables -------------------------------------------------

pub const CostSlot = struct { kind: i32, amt: i32 };

pub const ToolRow = struct {
    id: i32,
    kind: i32,
    cost: [3]CostSlot,
};

pub const UpgradeRow = struct {
    axis: i32,
    tier: i32,
    cost: [3]CostSlot,
};

pub const CosmeticRow = struct {
    name: []const u8,
    price: i32,
    unlock: i32,
};

pub const EncounterRow = struct { def_index: i32, weight: i32 };

pub const TextEntry = struct { key: []const u8, val: []const u8 };

pub const Rule = struct {
    cond_op: i32,
    cond_a: i32,
    cond_b: i32,
    effect_op: i32,
    effect_a: i32,
    effect_b: i32,
    timing: i32,
};

pub const Tables = struct {
    defs: [MAX_CREATURES]CreatureDef,
    def_count: i32,
    rules: [MAX_RULES]Rule,
    rule_count: i32,
    tools: [MAX_TOOLS]ToolRow,
    tool_count: i32,
    upgrades: [15]UpgradeRow,
    upgrade_count: i32,
    cosmetics: [MAX_COSMETICS]CosmeticRow,
    cosmetic_count: i32,
    encounters: [MAX_ZONES * 2 * MAX_ENCOUNTER]EncounterRow,
    enc_count: [MAX_ZONES * 2]i32,
    zone_cost: [MAX_ZONES]i32,
    zone_boss: [MAX_ZONES]i32,
    text_key: [MAX_TEXT_KEYS][]const u8,
    text_val: [MAX_TEXT_KEYS][]const u8,
    text_count: i32,
    content_version: i32,
    // 1 = data.loadFile succeeded, 0 = buildFallback/synthetic (P24/R10).
    loaded: i32,
};

pub var content_override: ?*Tables = null;

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
    pending_miss: i32,
    active_armor_pct: i32, active_resist_restrain: i32,
    rule_speed_add: i32, rule_atk_pct_add: i32,
    cond: i32,
    pending_stun: i32,
};

pub const FieldRecord = struct {
    cycles: i32, field_phases: i32,
    creatures_seen: i32, rares_seen: i32, bosses_killed: i32,
    final_phase2: i32,
    subdued: i32, killed: i32, overkilled: i32,
    expertise: [MAX_MATERIALS]i32,
    money_earned: i32, cosmetics: i32,
    boat: [5]i32,
};

pub const LastRun = struct {
    cycles: i32, phase2: i32, outcome: i32,
    actions: i32, hull_spent: i32, boss_kills: i32,
};

pub const World = struct {
    cycle: i32, phase: i32,
    ready: [MAX_ZONES * MAX_CREATURES]i32,
    seen_mask: [2]u32,
    journal_mask: [2]u32,
    journal_viewed: [2]u32,
    tooltip_shown: u32,
    field_phases: i32,
    release_bonus: [MAX_ZONES]i32,
    lockout_until: [MAX_ZONES]i32,
    family_overkill_mask: u32, wary_mask: [2]u32,
    rng_state: u32,
    hull: i32,
    boat: [5]i32, money: i32,
    expertise: [MAX_MATERIALS]i32,
    materials: [MAX_MATERIALS]i32,
    tools_owned: u32, tool_selected: i32,
    cosmetics_owned: u32, cosmetics_unlocked: u32,
    field_record_written: i32,
    field_record: FieldRecord,
    last_run: LastRun,
    score_subdued: i32, score_killed: i32, score_overkilled: i32,
    score_money_earned: i32,
    boss_variants_seen: u32, boss_kills: i32,
};

pub const LogEntry = struct { class: i32, msg_id: i32, a: i32, b: i32 };

pub const Expedition = struct {
    active: i32, zone: i32, fight_index: i32, seed: u32,
    hold: [MAX_PARTS]i32, hold_n: i32,
    tool: i32, tool_charge: i32, tool_broken: i32,
    pending_cond: i32,
};

pub const Effect = struct { op: i32, a: i32, b: i32 };

pub const GameState = struct {
    fight: FightState,
    world: World,
    log: [MAX_LOG]LogEntry,
    log_n: i32,
    exp: Expedition,
    screen: i32,
    // M10.1 transient field-action event (spec §7.1); never persisted.
    last_event: i32,
    last_event_def: i32,
    last_event_value: i32,
};

// One bounded fight-log append (spec §25.3). Shared so the tool lifecycle can
// record a break at the exact hull-hit moment without importing fight.zig.
pub fn appendLog(s: *GameState, class: i32, msg_id: i32, a: i32, b: i32) void {
    const e = LogEntry{ .class = class, .msg_id = msg_id, .a = a, .b = b };
    if (s.log_n < @intCast(i32, MAX_LOG)) {
        s.log[@intCast(usize, s.log_n)] = e;
        s.log_n += 1;
    } else {
        var i: usize = 1;
        while (i < MAX_LOG) : (i += 1) {
            s.log[i - 1] = s.log[i];
        }
        s.log[MAX_LOG - 1] = e;
    }
}

// ---- Action / outcome / bar / flag vocabulary ----------------------------

pub const ACT_STRIKE: i32 = 1;
pub const ACT_RESTRAIN: i32 = 2;
pub const ACT_EQUIP: i32 = 3;
pub const ACT_FLEE: i32 = 4;
pub const ACT_ATTEMPT: i32 = 5;
pub const ACT_DECLINE: i32 = 6;

pub const Action = struct { kind: i32, arg: i32 };

// ---- Tool ids / kinds (§10, §14.5) ---------------------------------------

pub const TOOL_PLATE: i32 = 1;
pub const TOOL_BRINE_NET: i32 = 2;
pub const TOOL_ELECTRIC_GLAND: i32 = 3;
pub const TOOL_LURE: i32 = 4;
pub const TOOL_PRESSURE_HOOK: i32 = 5;
pub const TOOL_SONAR: i32 = 6;
pub const TOOL_CORAL_SHIELD: i32 = 7;

pub const TOOL_KIND_ACTIVATED: i32 = 0;
pub const TOOL_KIND_RIGGED: i32 = 1;

pub const UNLOCK_Z1: i32 = 1;
pub const UNLOCK_Z2: i32 = 2;
pub const UNLOCK_Z3: i32 = 3;
pub const UNLOCK_DERELICT: i32 = 4;

// ---- Screen ids -----------------------------------------------------------

pub const SCREEN_FIGHT: i32 = 0;
pub const SCREEN_SUBDUE: i32 = 1;
pub const SCREEN_SUBDUE_POST: i32 = 2;

pub const SCREEN_W: i32 = 640;
pub const SCREEN_H: i32 = 480;

// ---- Nav screen ids -------------------------------------------------------

pub const NAV_DOCK: i32 = 10;
pub const NAV_MAP: i32 = 11;
pub const NAV_NODE: i32 = 12;
pub const NAV_SETTLE: i32 = 13;
pub const NAV_REFINE: i32 = 14;
pub const NAV_UPGRADE: i32 = 15;
pub const NAV_CRAFT: i32 = 16;
pub const NAV_BUY: i32 = 17;
pub const NAV_TOOLS: i32 = 18;
pub const NAV_LORE: i32 = 19;
pub const NAV_MENU: i32 = 20;
pub const NAV_SAVE_ERR: i32 = 21;
pub const NAV_JOURNAL: i32 = 22;
pub const NAV_HELP: i32 = 23;
pub const NAV_SUBDUE_INTRO: i32 = 24;
pub const NAV_QUIT: i32 = -1;

pub const NAV_RESULT_NONE: i32 = -100;
pub const NAV_RESULT_PREVIEW: i32 = -101;

// No fight is in progress: FightState.def_index is parked at this sentinel.
pub const NO_FIGHT: i32 = -1;

pub const OUT_ONGOING: i32 = 0;
pub const OUT_SUBDUE: i32 = 1;
pub const OUT_KILL: i32 = 2;
pub const OUT_OVERKILL: i32 = 3;
pub const OUT_CREATURE_FLED: i32 = 4;
pub const OUT_PLAYER_FLED: i32 = 5;

// ---- Field event ids (M10.1 §7.1) -----------------------------------------

pub const EV_NONE: i32 = 0;
pub const EV_DEPART: i32 = 1;
pub const EV_REST_NODE: i32 = 2;
pub const EV_ROUGH: i32 = 3;
pub const EV_REST_DOCK: i32 = 4;
pub const EV_SURFACE: i32 = 5;
pub const EV_SUBDUE: i32 = 6;
pub const EV_KILL: i32 = 7;
pub const EV_OVERKILL: i32 = 8;
pub const EV_CREATURE_FLED: i32 = 9;
pub const EV_PLAYER_FLED: i32 = 10;
pub const EV_ASCENT: i32 = 11;
pub const EV_HUNT_MAX: i32 = 12;
pub const EV_HUNT_EMPTY: i32 = 13;
pub const EV_RELEASED: i32 = 14;
pub const EV_SOLD: i32 = 15;
pub const EV_BOSS_LOCKED: i32 = 16;

pub const BAR_NONE: i32 = 0;
pub const BAR_STRIKE: i32 = 1;
pub const BAR_RESTRAIN: i32 = 2;

pub const LOG_NORMAL: i32 = 0;
pub const LOG_WARN: i32 = 1;
// Internal settlement record: entry.a = fight.def_index, entry.b = outcome.
pub const CLS_SECURED: i32 = 2;

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
pub const MSG_STRIKE: i32 = 2;
pub const MSG_RESTRAIN: i32 = 3;
pub const MSG_CREATURE_ATTACK: i32 = 4;
pub const MSG_SUBDUE_OK: i32 = 5;
pub const MSG_SUBDUE_FAIL: i32 = 6;
pub const MSG_KILL: i32 = 7;
pub const MSG_OVERKILL: i32 = 8;
pub const MSG_COUPLING: i32 = 9;
pub const MSG_DECLINE: i32 = 10;
pub const MSG_PLAYER_FLED: i32 = 11;
pub const MSG_CREATURE_FLED: i32 = 12;
pub const MSG_EQUIP: i32 = 13;
pub const MSG_DISCHARGE: i32 = 14;
// Decline copy used when no coupling regen is active (MSG_DECLINE keeps the
// active-regen wording).
pub const MSG_DECLINE_PLAIN: i32 = 15;
// Settlement record for the Secured line; renders the static row below.
pub const MSG_SECURED: i32 = 16;
pub const MSG_STUN: i32 = 17;
pub const MSG_BLIND: i32 = 18;
pub const MSG_INK: i32 = 19;
pub const MSG_DECOY: i32 = 20;
pub const MSG_PHASE: i32 = 21;
pub const MSG_LURE: i32 = 22;
pub const MSG_SONAR: i32 = 23;
pub const MSG_WARY: i32 = 24;
pub const MSG_GRUDGE: i32 = 25;
pub const MSG_TOOL_BROKEN: i32 = 26;
pub const MSG_EQUIP_REFUSED: i32 = 27;
pub const MSG_BLIND_ARMED: i32 = 28;
pub const MSG_INK_ARMED: i32 = 29;
pub const MSG_SUPPRESS_LURE: i32 = 30;
pub const MSG_SUPPRESS_SONAR: i32 = 31;
pub const MSG_SUPPRESS_HOOK: i32 = 32;
pub const MSG_SUPPRESS_SHIELD: i32 = 33;

// Content boot error copy (spec §25.10, §33).
pub const MSG_MISSING: []const u8 = "Content file missing. Reinstall from CD.";
pub const MSG_DAMAGED_PREFIX: []const u8 = "Content file is damaged at line ";
pub const MSG_DAMAGED_SUFFIX: []const u8 = ". Reinstall from CD.";

pub const MsgRow = struct { id: i32, text: []const u8 };

pub const MESSAGES = [_]MsgRow{
    MsgRow{
        .id = MSG_LAST_SURGE,
        .text = "Its will returns in a slow, deliberate wave.",
    },
    MsgRow{
        .id = MSG_SECURED,
        .text = "Secured.",
    },
    MsgRow{
        .id = 17,
        .text = "The creature is stunned and loses its action.",
    },
    MsgRow{
        .id = 18,
        .text = "Blinded - your Strike misses.",
    },
    MsgRow{
        .id = 19,
        .text = "Ink clouds the water - your action is forced.",
    },
    MsgRow{
        .id = 20,
        .text = "Your Strike tears through a decoy.",
    },
    MsgRow{
        .id = 21,
        .text = "The ray phases - your Strike passes through it.",
    },
    MsgRow{
        .id = 22,
        .text = "The lure reveals the creature's true shape.",
    },
    MsgRow{
        .id = 23,
        .text = "Sonar: speed and next action revealed.",
    },
    MsgRow{
        .id = MSG_WARY,
        .text = "This one remembers: +15 Resolve.",
    },
    MsgRow{
        .id = MSG_GRUDGE,
        .text = "It remembers the last run: +30 Resolve.",
    },
};

pub fn messageText(id: i32) ?[]const u8 {
    var i: usize = 0;
    while (i < MESSAGES.len) : (i += 1) {
        if (MESSAGES[i].id == id) return MESSAGES[i].text;
    }
    return null;
}
