// validate_test.zig — native Linux tests for M6 post-load validation.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/validate_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/validate_test"
//   "$OUT/validate_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const def = @import("../def.zig");
const data = @import("../data.zig");
const validate = @import("../validate.zig");

const DATA_PATH = "examples/z98/undersanded/data.z98";
const P_GOOD = "examples/z98/undersanded/tests/fixtures/data_good.z98";
const P_OVER = "examples/z98/undersanded/tests/fixtures/data_bad_over_capacity.z98";
const P_BOSS = "examples/z98/undersanded/tests/fixtures/data_bad_boss_sentinel.z98";
const P_NONBOSS = "examples/z98/undersanded/tests/fixtures/data_bad_nonboss_sentinel.z98";
const P_ROLE = "examples/z98/undersanded/tests/fixtures/data_bad_role.z98";
const P_FAMILY = "examples/z98/undersanded/tests/fixtures/data_bad_family.z98";
const P_ZONE_MASK = "examples/z98/undersanded/tests/fixtures/data_bad_zone_mask.z98";
const P_PHASE_MASK = "examples/z98/undersanded/tests/fixtures/data_bad_phase_mask.z98";
const P_SALE = "examples/z98/undersanded/tests/fixtures/data_bad_sale_zero.z98";
const P_RESPAWN = "examples/z98/undersanded/tests/fixtures/data_bad_respawn.z98";
const P_DROP_COUNT = "examples/z98/undersanded/tests/fixtures/data_bad_drop_count.z98";
const P_DROP_PART = "examples/z98/undersanded/tests/fixtures/data_bad_drop_part.z98";
const P_DUP_ID = "examples/z98/undersanded/tests/fixtures/data_bad_dup_creature_id.z98";
const P_DUP_NAME = "examples/z98/undersanded/tests/fixtures/data_bad_dup_creature_name.z98";
const P_EMPTY_NAME = "examples/z98/undersanded/tests/fixtures/data_bad_empty_creature_name.z98";
const P_NAME_COMMA = "examples/z98/undersanded/tests/fixtures/data_bad_creature_name_comma.z98";
const P_NAME_LONG = "examples/z98/undersanded/tests/fixtures/data_bad_creature_name_long.z98";
const P_RULE_OP = "examples/z98/undersanded/tests/fixtures/data_bad_rule_op.z98";
const P_RULE_OWNER = "examples/z98/undersanded/tests/fixtures/data_bad_rule_owner.z98";
const P_RULE_PART = "examples/z98/undersanded/tests/fixtures/data_bad_rule_partition.z98";
const P_TOOL0 = "examples/z98/undersanded/tests/fixtures/data_bad_tool_id0.z98";
const P_TOOL8 = "examples/z98/undersanded/tests/fixtures/data_bad_tool_id8.z98";
const P_TOOL_DUP = "examples/z98/undersanded/tests/fixtures/data_bad_dup_tool_id.z98";
const P_TOOL_COST = "examples/z98/undersanded/tests/fixtures/data_bad_tool_cost_kind.z98";
const P_TOOL_COST_DUP = "examples/z98/undersanded/tests/fixtures/data_bad_tool_cost_dup.z98";
const P_TOOL_KIND = "examples/z98/undersanded/tests/fixtures/data_bad_tool_kind.z98";
const P_ENC_REF = "examples/z98/undersanded/tests/fixtures/data_bad_encounter_ref.z98";
const P_ENC_WEIGHT = "examples/z98/undersanded/tests/fixtures/data_bad_encounter_weight.z98";
const P_ENC_SUM = "examples/z98/undersanded/tests/fixtures/data_bad_encounter_sum.z98";
const P_ENC_ZONE = "examples/z98/undersanded/tests/fixtures/data_bad_encounter_zone.z98";
const P_ENC_PHASE = "examples/z98/undersanded/tests/fixtures/data_bad_encounter_phase.z98";
const P_ZONE_COST = "examples/z98/undersanded/tests/fixtures/data_bad_zone_cost.z98";
const P_ZONE_BOSS = "examples/z98/undersanded/tests/fixtures/data_bad_zone_boss.z98";
const P_TEXT_MISSING = "examples/z98/undersanded/tests/fixtures/data_bad_text_manual_missing.z98";
const P_CONTENT = "examples/z98/undersanded/tests/fixtures/data_bad_content_version.z98";
const P_COS_COUNT = "examples/z98/undersanded/tests/fixtures/data_bad_cosmetic_count.z98";
const P_COS_UNLOCK0 = "examples/z98/undersanded/tests/fixtures/data_bad_cosmetic_unlock0.z98";
const P_COS_UNLOCK5 = "examples/z98/undersanded/tests/fixtures/data_bad_cosmetic_unlock5.z98";
const P_COS_PRICE = "examples/z98/undersanded/tests/fixtures/data_bad_cosmetic_price.z98";
const P_COS_NAME_LONG = "examples/z98/undersanded/tests/fixtures/data_bad_cosmetic_name_long.z98";
const P_COS_NAME_COMMA = "examples/z98/undersanded/tests/fixtures/data_bad_cosmetic_name_comma.z98";
const P_UP_MISSING = "examples/z98/undersanded/tests/fixtures/data_bad_upgrade_missing.z98";
const P_UP_DUP = "examples/z98/undersanded/tests/fixtures/data_bad_upgrade_dup.z98";
const P_UP_COST = "examples/z98/undersanded/tests/fixtures/data_bad_upgrade_cost_kind.z98";
const P_UP_COST_NEG = "examples/z98/undersanded/tests/fixtures/data_bad_upgrade_cost_neg.z98";

var fails: usize = 0;
var arena_buf: [256 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;

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

fn resetArena() void {
    arena = arena_mod.init(arena_buf[0..]);
}

// Load the fixture with the fallback preloaded, then validate; assert the
// first failure is exactly `want` at `line`.
fn expectErr(path: []const u8, want: data.LoadErr, line: i32) bool {
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    data.loadFile(&arena, path, &t) catch |e| {
        return e == want and data.err_line == line;
    };
    validate.validateAll(&t) catch |e| {
        return e == want and data.err_line == line;
    };
    return false;
}

fn loadsAndValidates(path: []const u8) bool {
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    data.loadFile(&arena, path, &t) catch return false;
    validate.validateAll(&t) catch return false;
    return true;
}

fn tFallbackClean() bool {
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    data.resetLines();
    validate.validateAll(&t) catch return false;
    return true;
}

fn tGoodClean() bool {
    return loadsAndValidates(P_GOOD);
}

fn tDataClean() bool {
    return loadsAndValidates(DATA_PATH);
}

fn tTextCapsSynthetic() bool {
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    data.resetLines();
    t.text_count = 257;
    validate.validateAll(&t) catch |e| {
        return e == error.TooMany and data.err_line == 0;
    };
    return false;
}

fn tManualEmptySynthetic() bool {
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    data.resetLines();
    t.text_count = 1;
    t.text_key[0] = "manual.1";
    t.text_val[0] = "";
    validate.validateAll(&t) catch |e| {
        return e == error.DamagedLine and data.err_line == 0;
    };
    return false;
}

fn tTextUnknownKeySynthetic() bool {
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    data.resetLines();
    t.text_count = 1;
    t.text_key[0] = "bogus.1";
    t.text_val[0] = "x";
    validate.validateAll(&t) catch |e| {
        return e == error.DamagedLine and data.err_line == 0;
    };
    return false;
}

fn loadPartition(t: *def.Tables) bool {
    resetArena();
    data.buildFallback(t);
    data.loadFile(&arena, P_RULE_PART, t) catch return false;
    return true;
}

fn tPartitionGap() bool {
    var t: def.Tables = undefined;
    if (!loadPartition(&t)) return false;
    var d0 = t.defs[0];
    d0.rule_count = 0;
    t.defs[0] = d0;
    validate.validateAll(&t) catch |e| {
        return e == error.BadRef and data.err_line == 6;
    };
    return false;
}

fn tPartitionOrphan() bool {
    var t: def.Tables = undefined;
    if (!loadPartition(&t)) return false;
    var d1 = t.defs[1];
    d1.rule_count = 0;
    t.defs[1] = d1;
    validate.validateAll(&t) catch |e| {
        return e == error.BadRef and data.err_line == 7;
    };
    return false;
}

fn tPartitionOverlap() bool {
    var t: def.Tables = undefined;
    if (!loadPartition(&t)) return false;
    var d1 = t.defs[1];
    d1.rule_start = 0;
    t.defs[1] = d1;
    validate.validateAll(&t) catch |e| {
        return e == error.BadRef and data.err_line == 6;
    };
    return false;
}

pub fn main() void {
    report("fallback_validates_clean", tFallbackClean());
    report("data_good_validates_clean", tGoodClean());
    report("data_z98_validates_clean", tDataClean());

    report("over_capacity_57_creatures", expectErr(P_OVER, error.Overflow, 59));
    report("boss_sentinel_wrong", expectErr(P_BOSS, error.BadSentinel, 3));
    report("nonboss_sentinel_minus1", expectErr(P_NONBOSS, error.BadSentinel, 3));
    report("role_out_of_range", expectErr(P_ROLE, error.BadRef, 3));
    report("family_out_of_range", expectErr(P_FAMILY, error.BadRef, 3));
    report("zone_mask_bad_bits", expectErr(P_ZONE_MASK, error.BadRef, 3));
    report("phase_mask_zero", expectErr(P_PHASE_MASK, error.BadRef, 3));
    report("sale_zero", expectErr(P_SALE, error.BadRef, 3));
    report("respawn_not_monotonic", expectErr(P_RESPAWN, error.BadRef, 3));
    report("drop_count_100", expectErr(P_DROP_COUNT, error.BadRef, 3));
    report("drop_part_14", expectErr(P_DROP_PART, error.BadRef, 3));
    report("duplicate_creature_id", expectErr(P_DUP_ID, error.BadRef, 4));
    report("duplicate_creature_name", expectErr(P_DUP_NAME, error.BadRef, 4));
    report("empty_creature_name", expectErr(P_EMPTY_NAME, error.DamagedLine, 3));
    report("creature_name_comma", expectErr(P_NAME_COMMA, error.DamagedLine, 3));
    report("creature_name_long", expectErr(P_NAME_LONG, error.DamagedLine, 3));

    report("rule_effect_op_out_of_range", expectErr(P_RULE_OP, error.BadRef, 5));
    report("rule_owner_unknown", expectErr(P_RULE_OWNER, error.BadRef, 5));
    report("rule_partition_gap", tPartitionGap());
    report("rule_partition_orphan", tPartitionOrphan());
    report("rule_partition_overlap", tPartitionOverlap());

    report("tool_id_zero", expectErr(P_TOOL0, error.BadRef, 3));
    report("tool_id_eight", expectErr(P_TOOL8, error.BadRef, 3));
    report("tool_id_duplicate", expectErr(P_TOOL_DUP, error.BadRef, 4));
    report("tool_cost_kind_10", expectErr(P_TOOL_COST, error.BadRef, 3));
    report("tool_cost_kind_duplicate", expectErr(P_TOOL_COST_DUP, error.BadRef, 3));
    report("tool_kind_out_of_range", expectErr(P_TOOL_KIND, error.BadRef, 3));

    report("encounter_def_index_bad", expectErr(P_ENC_REF, error.BadRef, 5));
    report("encounter_weight_zero", expectErr(P_ENC_WEIGHT, error.BadRef, 5));
    report("encounter_weight_sum", expectErr(P_ENC_SUM, error.BadRef, 5));
    report("encounter_zone_12", expectErr(P_ENC_ZONE, error.BadRef, 3));
    report("encounter_phase_2", expectErr(P_ENC_PHASE, error.BadRef, 3));
    report("zone_cost_negative", expectErr(P_ZONE_COST, error.BadRef, 3));
    report("zone_boss_not_bit", expectErr(P_ZONE_BOSS, error.BadRef, 3));

    report("manual1_missing_when_text", expectErr(P_TEXT_MISSING, error.DamagedLine, 2));
    report("content_version_not_2", expectErr(P_CONTENT, error.DamagedLine, 1));
    report("text_caps_257_keys_synthetic", tTextCapsSynthetic());
    report("manual1_empty_synthetic", tManualEmptySynthetic());
    report("text_unknown_key_synthetic", tTextUnknownKeySynthetic());

    report("cosmetic_count_not_12", expectErr(P_COS_COUNT, error.BadRef, 2));
    report("cosmetic_unlock_zero", expectErr(P_COS_UNLOCK0, error.BadRef, 3));
    report("cosmetic_unlock_five", expectErr(P_COS_UNLOCK5, error.BadRef, 3));
    report("cosmetic_price_zero", expectErr(P_COS_PRICE, error.BadRef, 3));
    report("cosmetic_name_long", expectErr(P_COS_NAME_LONG, error.DamagedLine, 3));
    report("cosmetic_name_comma", expectErr(P_COS_NAME_COMMA, error.DamagedLine, 3));

    report("upgrade_grid_missing_row", expectErr(P_UP_MISSING, error.BadRef, 15));
    report("upgrade_grid_duplicate_row", expectErr(P_UP_DUP, error.BadRef, 30));
    report("upgrade_cost_kind_10", expectErr(P_UP_COST, error.BadRef, 16));
    report("upgrade_cost_kind_negative", expectErr(P_UP_COST_NEG, error.BadRef, 16));

    data.uninstall();
    if (fails != 0) os.exit(1);
    io.write("validate_test PASS\n");
}
