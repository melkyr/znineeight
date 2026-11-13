// game.zig — UNDERSANDED pure game state machine (spec §22, §25.3).
//
// No I/O, no rendering: takes *GameState + Action, mutates flat structs, and
// appends to the fixed 64-entry combat log (drop-oldest). All action handling
// delegates to fight.zig, which owns §9.2 resolution order.

const def = @import("def.zig");
const fight = @import("fight.zig");
const creatures = @import("creatures_t1.zig");

// M2 hardcodes the expedition stream (spec §25.5 seed formula).
pub const EXPEDITION_SEED: u32 = 98;
pub const FIGHT_INDEX: i32 = 0;

fn zeroWorld(w: *def.World) void {
    w.cycle = 0;
    w.phase = 0;
    var i: usize = 0;
    while (i < def.MAX_ZONES * def.MAX_CREATURES) : (i += 1) {
        w.ready[i] = 0;
    }
    w.seen_mask[0] = 0;
    w.seen_mask[1] = 0;
    w.journal_mask[0] = 0;
    w.journal_mask[1] = 0;
    w.tooltip_shown = 0;
    w.field_phases = 0;
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        w.release_bonus[i] = 0;
        w.lockout_until[i] = 0;
    }
    w.family_overkill_mask = 0;
    w.wary_mask[0] = 0;
    w.wary_mask[1] = 0;
    w.rng_state = 0;
    i = 0;
    while (i < 5) : (i += 1) {
        w.boat[i] = 0;
    }
    w.money = 0;
    i = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        w.expertise[i] = 0;
    }
    w.cosmetics_owned = 0;
    w.cosmetics_unlocked = 0;
    w.field_record_written = 0;
    w.boss_variants_seen = 0;
    w.boss_kills = 0;
}

pub fn startFight(s: *def.GameState, def_index: i32) void {
    s.exp.seed = EXPEDITION_SEED;
    s.exp.fight_index = FIGHT_INDEX;
    s.exp.active = 0;
    s.exp.zone = 0;
    zeroWorld(&s.world);

    var d = creatures.defAt(def_index);
    fight.startFightDef(s, def_index, &d, creatures.RULES[0..]);
}

pub fn gameStep(s: *def.GameState, a: def.Action) void {
    switch (a.kind) {
        def.ACT_STRIKE, def.ACT_RESTRAIN, def.ACT_EQUIP, def.ACT_FLEE, def.ACT_ATTEMPT, def.ACT_DECLINE => {
            const index = s.fight.def_index;
            var d = creatures.defAt(index);
            fight.step(s, a, &d, creatures.RULES[0..]);
        },
        else => {},
    }
}
