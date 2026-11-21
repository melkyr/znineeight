// score.zig — UNDERSANDED score data (spec §19, §25.7, §38 P31).

const def = @import("def.zig");
const creatures = @import("creatures_t1.zig");

pub const TITLE_FIELD_RECORD: []const u8 = "FIELD RECORD";
pub const TITLE_VARIANTS_SEEN: []const u8 = "VARIANTS SEEN";
pub const TITLE_LAST_RUN: []const u8 = "LAST RUN";
pub const CLOSING: []const u8 = "Thank you for playing. The ocean is still there.";

pub const CREDITS_TITLE: []const u8 = "UNDERSANDED";
pub const CREDITS_SUBTITLE: []const u8 = "A Z98 demo.";
pub const CREDITS_BYLINE: []const u8 = "Design, code, art, and data by the Undersanded team.";
pub const CREDITS_CONTINUE: []const u8 = "[C]ontinue";

pub const VARIANT_COUNT: i32 = 5;
pub const OUTCOME_ASCENT: i32 = -1;

pub const IDENTITIES = [VARIANT_COUNT][]const u8{
    "The Armor",
    "The Sliver",
    "The Hoard",
    "The Drown",
    "The Blur",
};

pub const ScorePanels = struct {
    field_written: i32,
    field: def.FieldRecord,
    variants_seen: u32,
    variants_count: i32,
    last: def.LastRun,
    creatures_total: i32,
    rares_total: i32,
};

fn defBitSet(mask: *const [2]u32, d: i32) bool {
    if (d < 0) return false;
    if (d >= @intCast(i32, def.MAX_CREATURES)) return false;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    const m: u32 = @intCast(u32, 1) << bit;
    return (mask[word] & m) != 0;
}

fn popcount(mask: u32) i32 {
    var x = mask;
    var n: i32 = 0;
    while (x != 0) {
        n += @intCast(i32, x & 1);
        x = x >> 1;
    }
    return n;
}

fn clampVariant(v: i32) i32 {
    if (v < 0 or v >= VARIANT_COUNT) return 0;
    return v;
}

pub fn identityLabel(v: i32) []const u8 {
    const at = clampVariant(v);
    return IDENTITIES[@intCast(usize, at)];
}

pub fn outcomeLabel(o: i32) []const u8 {
    switch (o) {
        def.OUT_KILL => return "Kill",
        def.OUT_OVERKILL => return "Overkill",
        def.OUT_PLAYER_FLED => return "Fled",
        OUTCOME_ASCENT => return "Ascent",
        else => return "Lost",
    }
}

pub fn countSeen(w: *const def.World) i32 {
    var n: i32 = 0;
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (defBitSet(&w.seen_mask, d)) n += 1;
    }
    return n;
}

pub fn countRaresSeen(w: *const def.World) i32 {
    var n: i32 = 0;
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (creatures.defAt(d).role != creatures.ROLE_RARE) continue;
        if (defBitSet(&w.seen_mask, d)) n += 1;
    }
    return n;
}

pub fn creatureTotal() i32 {
    return creatures.defCount();
}

pub fn rareTotal() i32 {
    var n: i32 = 0;
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (creatures.defAt(d).role == creatures.ROLE_RARE) n += 1;
    }
    return n;
}

pub fn variantsCount(mask: u32) i32 {
    return popcount(mask & 0x1F);
}

pub fn scoreSnapshot(w: *def.World) ScorePanels {
    return ScorePanels{
        .field_written = w.field_record_written,
        .field = w.field_record,
        .variants_seen = w.boss_variants_seen,
        .variants_count = variantsCount(w.boss_variants_seen),
        .last = w.last_run,
        .creatures_total = creatureTotal(),
        .rares_total = rareTotal(),
    };
}

pub fn freezeFieldRecord(w: *def.World, final_phase2: i32) void {
    if (w.field_record_written != 0) return;

    var fr: def.FieldRecord = undefined;
    fr.cycles = w.cycle;
    fr.field_phases = w.field_phases;
    fr.creatures_seen = countSeen(w);
    fr.rares_seen = countRaresSeen(w);
    fr.bosses_killed = w.boss_kills;
    fr.final_phase2 = clampVariant(final_phase2);
    fr.subdued = w.score_subdued;
    fr.killed = w.score_killed;
    fr.overkilled = w.score_overkilled;
    var i: usize = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        fr.expertise[i] = w.expertise[i];
    }
    fr.money_earned = w.score_money_earned;
    fr.cosmetics = popcount(w.cosmetics_owned);
    i = 0;
    while (i < 5) : (i += 1) {
        fr.boat[i] = w.boat[i];
    }
    w.field_record = fr;
    w.field_record_written = 1;
}

pub fn recordLastRun(w: *def.World, f: *const def.FightState, outcome: i32) void {
    w.last_run = def.LastRun{
        .cycles = w.cycle,
        .phase2 = clampVariant(f.boss_variant),
        .outcome = outcome,
        .actions = f.actions,
        .hull_spent = f.hull_spent,
        .boss_kills = w.boss_kills,
    };
}

pub fn recordBossRun(g: *def.GameState, outcome: i32) void {
    if ((g.fight.flags & def.F_BOSS) == 0) return;
    if (g.fight.boss_phase == 0) return;
    recordLastRun(&g.world, &g.fight, outcome);
}

pub const CREDITS_LINES = [4][]const u8{
    CREDITS_TITLE,
    CREDITS_SUBTITLE,
    CREDITS_BYLINE,
    CREDITS_CONTINUE,
};
