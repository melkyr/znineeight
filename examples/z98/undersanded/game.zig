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

pub fn startFight(s: *def.GameState, def_index: i32) void {
    s.exp.seed = EXPEDITION_SEED;
    s.exp.fight_index = FIGHT_INDEX;

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
