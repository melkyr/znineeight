// data_content_test.zig — native Linux assertions for the shipped M6
// data.z98 content: table counts, Z1-Z3 encounter sums, empty Z4-Z8 phases,
// the 12-zone cost/boss ladder, and manual.1 (P24).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/data_content_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/data_content_test"
//   "$OUT/data_content_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const def = @import("../def.zig");
const data = @import("../data.zig");
const validate = @import("../validate.zig");

const DATA_PATH = "examples/z98/undersanded/data.z98";

const ZONE_COST: [def.MAX_ZONES]i32 = .{ 1, 2, 3, 3, 4, 4, 5, 5, 5, 0, 0, 0 };

var fails: usize = 0;
var arena_buf: [256 * 1024]u8 = undefined;

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

fn bytesEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn textFind(t: *const def.Tables, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < @intCast(usize, t.text_count)) : (i += 1) {
        if (bytesEq(t.text_key[i], key)) return t.text_val[i];
    }
    return null;
}

fn encSum(t: *const def.Tables, zone: i32, phase: i32) i32 {
    const ci: usize = @intCast(usize, zone) * 2 + @intCast(usize, phase);
    const base: usize = @intCast(usize, zone) * 2 * def.MAX_ENCOUNTER +
        @intCast(usize, phase) * def.MAX_ENCOUNTER;
    const n: usize = @intCast(usize, t.enc_count[ci]);
    var sum: i32 = 0;
    var j: usize = 0;
    while (j < n) : (j += 1) {
        sum += t.encounters[base + j].weight;
    }
    return sum;
}

fn zones4to8Empty(t: *const def.Tables) bool {
    var z: i32 = 3;
    while (z <= 7) : (z += 1) {
        var ph: i32 = 0;
        while (ph < 2) : (ph += 1) {
            const ci: usize = @intCast(usize, z) * 2 + @intCast(usize, ph);
            if (t.enc_count[ci] != 0) return false;
        }
    }
    return true;
}

fn zoneCostLadder(t: *const def.Tables) bool {
    if (def.MAX_ZONES != 12) return false;
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        if (t.zone_cost[i] != ZONE_COST[i]) return false;
    }
    return true;
}

fn zone8BossOnly(t: *const def.Tables) bool {
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        const want: i32 = if (i == 8) 1 else 0;
        if (t.zone_boss[i] != want) return false;
    }
    return true;
}

fn manualPresentNonEmpty(t: *const def.Tables) bool {
    const v = textFind(t, "manual.1") orelse return false;
    return v.len > 0;
}

pub fn main() void {
    var arena = arena_mod.init(arena_buf[0..]);
    var t: def.Tables = undefined;
    var loaded = true;
    data.loadFile(&arena, DATA_PATH, &t) catch {
        loaded = false;
    };
    report("shipped_data_loads", loaded);

    var valid = false;
    if (loaded) {
        valid = true;
        validate.validateAll(&t) catch {
            valid = false;
        };
    }
    report("shipped_data_validates_clean", valid);

    report("defs_18", loaded and t.def_count == 18);
    report("rules_4", loaded and t.rule_count == 4);
    report("tools_7", loaded and t.tool_count == 7);
    report("upgrades_15", loaded and t.upgrade_count == 15);
    report("cosmetics_12", loaded and t.cosmetic_count == 12);

    report("encounters_z1_day_sum_100", loaded and encSum(&t, 0, 0) == 100);
    report("encounters_z1_night_sum_100", loaded and encSum(&t, 0, 1) == 100);
    report("encounters_z2_day_sum_100", loaded and encSum(&t, 1, 0) == 100);
    report("encounters_z2_night_sum_100", loaded and encSum(&t, 1, 1) == 100);
    report("encounters_z3_day_sum_100", loaded and encSum(&t, 2, 0) == 100);
    report("encounters_z3_night_sum_100", loaded and encSum(&t, 2, 1) == 100);
    report("encounters_z4_z8_phases_empty", loaded and zones4to8Empty(&t));

    report("zones_12_cost_ladder", loaded and zoneCostLadder(&t));
    report("zone8_boss_only", loaded and zone8BossOnly(&t));
    report("manual_1_present_nonempty", loaded and manualPresentNonEmpty(&t));

    if (fails != 0) os.exit(1);
    io.write("data_content_test PASS\n");
}
