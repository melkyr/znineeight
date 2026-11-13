// behavior_test.zig — native Linux tests for the M2 behavior rule VM (§25.6).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/behavior_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/behavior_test"
//   "$OUT/behavior_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const std_math = @import("std_math");
const behavior = @import("../behavior.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn makeRule(cond_op: i32, cond_a: i32, cond_b: i32, effect_op: i32, effect_a: i32, effect_b: i32, timing: i32) behavior.Rule {
    return behavior.Rule{
        .cond_op = cond_op,
        .cond_a = cond_a,
        .cond_b = cond_b,
        .effect_op = effect_op,
        .effect_a = effect_a,
        .effect_b = effect_b,
        .timing = timing,
    };
}

fn bitMask(bit: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, bit);
}

fn tHpBelowPersistent() bool {
    const r = makeRule(behavior.HP_BELOW, 50, 0, behavior.REGEN_HP, 5, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    const e1 = behavior.ruleFire(r, 60, 49, 100, 100, 1, &c, 0) orelse return false;
    if (e1.op != behavior.REGEN_HP) return false;
    if (e1.a != 5) return false;

    const e2 = behavior.ruleFire(r, 49, 49, 100, 100, 2, &c, 0) orelse return false;
    if (e2.a != 5) return false;
    if (c != 0) return false;
    if (behavior.ruleFire(r, 50, 50, 100, 100, 3, &c, 0) != null) return false;
    if (behavior.ruleFire(r, 49, 60, 100, 100, 4, &c, 0) != null) return false;
    return true;
}

fn tHpBelowOneshot() bool {
    const r = makeRule(behavior.HP_BELOW, 50, 0, behavior.HULL_DMG, 8, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0;

    const e = behavior.ruleFire(r, 60, 49, 100, 100, 1, &c, 3) orelse return false;
    if (e.op != behavior.HULL_DMG) return false;
    if (e.a != 8) return false;
    if ((c & bitMask(3)) == 0) return false;
    if (behavior.ruleFire(r, 49, 49, 100, 100, 2, &c, 3) != null) return false;
    if (behavior.ruleFire(r, 60, 49, 100, 100, 3, &c, 3) != null) return false;

    var c2: u32 = 0;
    if (behavior.ruleFire(r, 40, 30, 100, 100, 1, &c2, 4) != null) return false;
    if (c2 != 0) return false;
    if (behavior.ruleFire(r, 60, 50, 100, 100, 1, &c2, 5) != null) return false;
    if (behavior.ruleFire(r, 49, 60, 100, 100, 1, &c2, 6) != null) return false;
    if (behavior.ruleFire(r, 50, 50, 100, 100, 1, &c2, 7) != null) return false;
    return true;
}

fn tResBelowPersistent() bool {
    const r = makeRule(behavior.RES_BELOW, 50, 0, behavior.REGEN_RES, 6, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    const e1 = behavior.ruleFire(r, 100, 100, 60, 49, 1, &c, 0) orelse return false;
    if (e1.op != behavior.REGEN_RES) return false;
    if (e1.a != 6) return false;

    const e2 = behavior.ruleFire(r, 100, 100, 49, 49, 2, &c, 0) orelse return false;
    if (e2.a != 6) return false;
    if (c != 0) return false;
    if (behavior.ruleFire(r, 100, 100, 50, 50, 3, &c, 0) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 49, 60, 4, &c, 0) != null) return false;
    return true;
}

fn tResBelowOneshot() bool {
    const r = makeRule(behavior.RES_BELOW, 50, 0, behavior.MISS_STRIKE, 1, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0;

    const e = behavior.ruleFire(r, 100, 100, 60, 49, 1, &c, 5) orelse return false;
    if (e.op != behavior.MISS_STRIKE) return false;
    if (e.a != 1) return false;
    if ((c & bitMask(5)) == 0) return false;
    if (behavior.ruleFire(r, 100, 100, 60, 49, 2, &c, 5) != null) return false;

    var c2: u32 = 0;
    if (behavior.ruleFire(r, 100, 100, 40, 30, 1, &c2, 6) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 60, 50, 1, &c2, 7) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 49, 60, 1, &c2, 8) != null) return false;
    return true;
}

fn tRoundModPersistent() bool {
    const r = makeRule(behavior.ROUND_MOD, 3, 1, behavior.ADD_SPEED, 4, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 0) == null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 2, &c, 0) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 3, &c, 0) != null) return false;
    const e = behavior.ruleFire(r, 100, 100, 100, 100, 4, &c, 0) orelse return false;
    if (e.a != 4) return false;
    if (c != 0) return false;

    const zero = makeRule(behavior.ROUND_MOD, 0, 0, behavior.ADD_SPEED, 4, 0, behavior.TIMING_PERSISTENT);
    if (behavior.ruleFire(zero, 100, 100, 100, 100, 3, &c, 0) != null) return false;
    return true;
}

fn tRoundModOneshot() bool {
    const r = makeRule(behavior.ROUND_MOD, 3, 1, behavior.SET_ARMOR, 60, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 9) == null) return false;
    if ((c & bitMask(9)) == 0) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 4, &c, 9) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 7, &c, 9) != null) return false;

    var c2: u32 = 0;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 2, &c2, 10) != null) return false;
    if (c2 != 0) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 4, &c2, 10) == null) return false;
    return true;
}

fn tFirstRoundPersistent() bool {
    const r = makeRule(behavior.FIRST_ROUND, 0, 0, behavior.SET_FLEE, 1, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 0) == null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 0) == null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 2, &c, 0) != null) return false;
    if (c != 0) return false;
    return true;
}

fn tFirstRoundOneshot() bool {
    const r = makeRule(behavior.FIRST_ROUND, 0, 0, behavior.SET_INK, 1, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 11) == null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 11) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 2, &c, 11) != null) return false;

    var c2: u32 = 0;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 2, &c2, 12) != null) return false;
    return true;
}

fn tAlwaysPersistent() bool {
    const r = makeRule(behavior.ALWAYS, 0, 0, behavior.MULT_ATK, 150, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    const e1 = behavior.ruleFire(r, 100, 100, 100, 100, 0, &c, 0) orelse return false;
    if (e1.op != behavior.MULT_ATK) return false;
    if (e1.a != 150) return false;
    if (behavior.ruleFire(r, 0, 0, 0, 0, 5, &c, 0) == null) return false;
    if (c != 0) return false;
    return true;
}

fn tAlwaysOneshot() bool {
    const r = makeRule(behavior.ALWAYS, 0, 0, behavior.REGEN_RES, 3, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 100, 100, 100, 100, 0, &c, 13) == null) return false;
    if ((c & bitMask(13)) == 0) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 0, &c, 13) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 13) != null) return false;
    return true;
}

fn tUnknownCondNoop() bool {
    const r = makeRule(99, 50, 0, behavior.HULL_DMG, 8, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;
    if (behavior.ruleFire(r, 100, 0, 100, 0, 1, &c, 0) != null) return false;

    const one = makeRule(99, 50, 0, behavior.HULL_DMG, 8, 0, behavior.TIMING_ONESHOT);
    if (behavior.ruleFire(one, 100, 0, 100, 0, 1, &c, 1) != null) return false;
    if (c != 0) return false;
    return true;
}

fn tUnknownEffectNoop() bool {
    const r = makeRule(behavior.ALWAYS, 0, 0, 99, 8, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 0) != null) return false;

    const one = makeRule(behavior.HP_BELOW, 50, 0, 99, 8, 0, behavior.TIMING_ONESHOT);
    if (behavior.ruleFire(one, 60, 49, 100, 100, 1, &c, 2) != null) return false;
    if (c != 0) return false;
    return true;
}

fn tUnknownTimingNoop() bool {
    const r = makeRule(behavior.ALWAYS, 0, 0, behavior.HULL_DMG, 8, 0, 2);
    var c: u32 = 0;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 0) != null) return false;
    if (c != 0) return false;
    return true;
}

fn tConsumedBitIsolation() bool {
    const r = makeRule(behavior.HP_BELOW, 50, 0, behavior.HULL_DMG, 8, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 60, 49, 100, 100, 1, &c, 31) == null) return false;
    if (c != 0x80000000) return false;
    if (behavior.ruleFire(r, 60, 49, 100, 100, 2, &c, 31) != null) return false;

    if (behavior.ruleFire(r, 60, 49, 100, 100, 3, &c, 0) == null) return false;
    if (c != 0x80000001) return false;
    if (behavior.ruleFire(r, 60, 49, 100, 100, 4, &c, 0) != null) return false;
    return true;
}

fn tSetBlindChanceInB() bool {
    const r = makeRule(behavior.RES_BELOW, 50, 0, behavior.SET_BLIND, 0, 50, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    const e = behavior.ruleFire(r, 100, 100, 60, 49, 1, &c, 0) orelse return false;
    if (e.op != behavior.SET_BLIND) return false;
    if (e.a != 0) return false;
    if (e.b != 50) return false;
    const e2 = behavior.ruleFire(r, 100, 100, 49, 49, 2, &c, 0) orelse return false;
    if (e2.b != 50) return false;
    return true;
}

fn tEffectVocabulary() bool {
    var op: i32 = behavior.REGEN_RES;
    while (op <= behavior.MISS_STRIKE) : (op += 1) {
        const r = makeRule(behavior.ALWAYS, 0, 0, op, 7, 9, behavior.TIMING_PERSISTENT);
        var c: u32 = 0;
        const e = behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 0) orelse return false;
        if (e.op != op) return false;
        if (e.a != 7) return false;
        if (e.b != 9) return false;
    }
    return true;
}

fn tConditionOpValuesFrozen() bool {
    if (behavior.HP_BELOW != 1) return false;
    if (behavior.RES_BELOW != 2) return false;
    if (behavior.ROUND_MOD != 3) return false;
    if (behavior.FIRST_ROUND != 4) return false;
    if (behavior.ALWAYS != 5) return false;
    return true;
}

fn tEffectOpValuesFrozen() bool {
    if (behavior.REGEN_RES != 1) return false;
    if (behavior.REGEN_HP != 2) return false;
    if (behavior.HULL_DMG != 3) return false;
    if (behavior.SET_ARMOR != 4) return false;
    if (behavior.SET_FLEE != 5) return false;
    if (behavior.SET_BLIND != 6) return false;
    if (behavior.SET_INK != 7) return false;
    if (behavior.ADD_SPEED != 8) return false;
    if (behavior.MULT_ATK != 9) return false;
    if (behavior.MISS_STRIKE != 10) return false;
    return true;
}

fn tHpBelowCrossingBoundary() bool {
    const r = makeRule(behavior.HP_BELOW, 50, 0, behavior.HULL_DMG, 8, 0, behavior.TIMING_ONESHOT);

    var c: u32 = 0;
    if (behavior.ruleFire(r, 50, 49, 100, 100, 1, &c, 0) == null) return false;
    if ((c & bitMask(0)) == 0) return false;

    var c2: u32 = 0;
    if (behavior.ruleFire(r, 50, 50, 100, 100, 1, &c2, 1) != null) return false;
    if (c2 != 0) return false;
    return true;
}

fn tInvalidBitNoop() bool {
    const r = makeRule(behavior.ALWAYS, 0, 0, behavior.HULL_DMG, 8, 0, behavior.TIMING_ONESHOT);
    var c: u32 = 0x12345678;

    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, -1) != null) return false;
    if (c != 0x12345678) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 32) != null) return false;
    if (c != 0x12345678) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 1, &c, 99) != null) return false;
    if (c != 0x12345678) return false;
    return true;
}

fn tRoundModNegativeArg() bool {
    const r = makeRule(behavior.ROUND_MOD, -3, 0, behavior.ADD_SPEED, 4, 0, behavior.TIMING_PERSISTENT);
    var c: u32 = 0;

    if (behavior.ruleFire(r, 100, 100, 100, 100, -6, &c, 0) == null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 5, &c, 0) != null) return false;
    if (behavior.ruleFire(r, 100, 100, 100, 100, 0, &c, 0) == null) return false;
    return true;
}

fn tStdMathClampEdges() bool {
    if (std_math.clamp(-1, 0, 10) != 0) return false;
    if (std_math.clamp(0, 0, 10) != 0) return false;
    if (std_math.clamp(5, 0, 10) != 5) return false;
    if (std_math.clamp(10, 0, 10) != 10) return false;
    if (std_math.clamp(11, 0, 10) != 10) return false;
    return true;
}

fn tStdMathAbsNegMax() bool {
    if (std_math.abs(-2147483647) != 2147483647) return false;
    if (std_math.abs(2147483647) != 2147483647) return false;
    if (std_math.abs(0) != 0) return false;
    if (std_math.abs(-1) != 1) return false;
    return true;
}

fn tStdMathMinMax() bool {
    if (std_math.min(-5, 2) != -5) return false;
    if (std_math.min(2, 2) != 2) return false;
    if (std_math.max(-5, 2) != 2) return false;
    if (std_math.max(2, 2) != 2) return false;
    return true;
}

pub fn main() void {
    report("hp_below_persistent", tHpBelowPersistent());
    report("hp_below_oneshot_crossing_once", tHpBelowOneshot());
    report("res_below_persistent", tResBelowPersistent());
    report("res_below_oneshot_crossing_once", tResBelowOneshot());
    report("round_mod_persistent", tRoundModPersistent());
    report("round_mod_oneshot", tRoundModOneshot());
    report("first_round_persistent", tFirstRoundPersistent());
    report("first_round_oneshot", tFirstRoundOneshot());
    report("always_persistent", tAlwaysPersistent());
    report("always_oneshot", tAlwaysOneshot());
    report("unknown_cond_noop", tUnknownCondNoop());
    report("unknown_effect_noop", tUnknownEffectNoop());
    report("unknown_timing_noop", tUnknownTimingNoop());
    report("consumed_bit_isolation", tConsumedBitIsolation());
    report("set_blind_chance_in_b", tSetBlindChanceInB());
    report("effect_vocabulary", tEffectVocabulary());
    report("condition_op_values_frozen", tConditionOpValuesFrozen());
    report("effect_op_values_frozen", tEffectOpValuesFrozen());
    report("hp_below_crossing_boundary", tHpBelowCrossingBoundary());
    report("invalid_bit_noop", tInvalidBitNoop());
    report("round_mod_negative_arg", tRoundModNegativeArg());
    report("std_math_clamp_edges", tStdMathClampEdges());
    report("std_math_abs_neg_max", tStdMathAbsNegMax());
    report("std_math_min_max", tStdMathMinMax());

    if (fails != 0) os.exit(1);
    io.write("behavior_test PASS\n");
}
