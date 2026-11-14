// behavior.zig — UNDERSANDED behavior rule VM (spec §25.6).
//
// A flat, serializable rule table replaces function pointers (R4/R5). One-shot
// rows (timing 0) fire when a threshold is crossed (`prev >= threshold &&
// now < threshold`) and set a consumed bit; persistent rows (timing 1) report
// the effect on every evaluation while the condition holds. Unknown condition,
// effect, or timing values are a no-op. All tuning constants are module-level
// (R2) and every switch has an else (R3).

const def = @import("def.zig");

pub const Rule = struct {
    cond_op: i32,
    cond_a: i32,
    cond_b: i32,
    effect_op: i32,
    effect_a: i32,
    effect_b: i32,
    timing: i32,
};

// ---- Condition op vocabulary ---------------------------------------------

pub const HP_BELOW: i32 = 1;
pub const RES_BELOW: i32 = 2;
pub const ROUND_MOD: i32 = 3;
pub const FIRST_ROUND: i32 = 4;
pub const ALWAYS: i32 = 5;

// ---- Effect op vocabulary -------------------------------------------------

pub const REGEN_RES: i32 = 1;
pub const REGEN_HP: i32 = 2;
pub const HULL_DMG: i32 = 3;
pub const SET_ARMOR: i32 = 4;
pub const SET_FLEE: i32 = 5;
pub const SET_BLIND: i32 = 6;
pub const SET_INK: i32 = 7;
pub const ADD_SPEED: i32 = 8;
pub const MULT_ATK: i32 = 9;
pub const MISS_STRIKE: i32 = 10;

// ---- Timing vocabulary ----------------------------------------------------

pub const TIMING_ONESHOT: i32 = 0;
pub const TIMING_PERSISTENT: i32 = 1;

// First round number; kept module-level so no switch case owns a local const.
pub const FIRST_ROUND_NUM: i32 = 1;

fn effectKnown(op: i32) bool {
    switch (op) {
        REGEN_RES, REGEN_HP, HULL_DMG, SET_ARMOR, SET_FLEE,
        SET_BLIND, SET_INK, ADD_SPEED, MULT_ATK, MISS_STRIKE => return true,
        else => return false,
    }
}

pub fn ruleFire(r: Rule, prev_hp: i32, now_hp: i32, prev_res: i32, now_res: i32, round: i32, consumed: *u32, bit: i32) ?def.Effect {
    var holds: bool = false;
    var crossed: bool = false;
    switch (r.cond_op) {
        HP_BELOW => {
            holds = now_hp < r.cond_a;
            crossed = prev_hp >= r.cond_a and now_hp < r.cond_a;
        },
        RES_BELOW => {
            holds = now_res < r.cond_a;
            crossed = prev_res >= r.cond_a and now_res < r.cond_a;
        },
        ROUND_MOD => {
            if (r.cond_a == 0) {
                holds = false;
            } else {
                holds = (round % r.cond_a) == r.cond_b;
            }
            crossed = holds;
        },
        FIRST_ROUND => {
            holds = round == FIRST_ROUND_NUM;
            crossed = holds;
        },
        ALWAYS => {
            holds = true;
            crossed = true;
        },
        else => return null,
    }

    if (!effectKnown(r.effect_op)) return null;

    if (r.timing == TIMING_ONESHOT) {
        if (!crossed) return null;
        if (bit < 0 or bit >= 32) return null;
        const mask: u32 = @intCast(u32, 1) << @intCast(u32, bit);
        if ((consumed.* & mask) != 0) return null;
        consumed.* = consumed.* | mask;
        return def.Effect{ .op = r.effect_op, .a = r.effect_a, .b = r.effect_b };
    }
    if (r.timing == TIMING_PERSISTENT) {
        if (!holds) return null;
        return def.Effect{ .op = r.effect_op, .a = r.effect_a, .b = r.effect_b };
    }
    return null;
}
