// replay_test.zig — native Linux tests for the M3 replay v2 format (§28) and
// fight determinism (§34 "Subdue determinism").
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/replay_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/replay_test"
//   "$OUT/replay_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const fight = @import("../fight.zig");
const creatures = @import("../creatures_t1.zig");
const replay = @import("../replay.zig");

const REPLAY_DEFAULT = "/tmp/m3_t1_replay_test.rep";

fn replayPath() []const u8 {
    if (os.env("UNDERSANDED_REPLAY_PATH")) |p| {
        if (p.len > 0) return p;
    }
    return REPLAY_DEFAULT;
}

fn cleanupDefault() void {
    if (os.env("UNDERSANDED_REPLAY_PATH")) |p| {
        _ = p;
    } else {
        file_mod.remove(REPLAY_DEFAULT) catch {};
    }
}

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

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn tRoundTrip() bool {
    const path = replayPath();
    file_mod.remove(path) catch {};
    const acts = [6]def.Action{
        def.Action{ .kind = def.ACT_STRIKE, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_EQUIP, .arg = 0 },
        def.Action{ .kind = def.ACT_FLEE, .arg = 0 },
        def.Action{ .kind = def.ACT_ATTEMPT, .arg = 0 },
        def.Action{ .kind = def.ACT_DECLINE, .arg = 0 },
    };

    if (!replay.replayWrite(path, 98, "eel", "Z3", "night", "sonar", acts[0..])) return false;

    var r: replay.Replay = undefined;
    if (!replay.replayRead(path, &r)) return false;
    if (r.seed != 98) return false;
    if (!eq(replay.creatureText(&r), "eel")) return false;
    if (!eq(replay.zoneText(&r), "Z3")) return false;
    if (!eq(replay.phaseText(&r), "night")) return false;
    if (!eq(replay.toolText(&r), "sonar")) return false;
    if (r.action_n != 6) return false;

    var i: usize = 0;
    while (i < acts.len) : (i += 1) {
        if (r.acts[i].kind != acts[i].kind) return false;
        if (r.acts[i].arg != acts[i].arg) return false;
    }
    return true;
}

fn tExactBytes() bool {
    const path = replayPath();
    file_mod.remove(path) catch {};
    const acts = [2]def.Action{
        def.Action{ .kind = def.ACT_STRIKE, .arg = 0 },
        def.Action{ .kind = def.ACT_DECLINE, .arg = 0 },
    };
    if (!replay.replayWrite(path, 98, "eel", "Z3", "night", "sonar", acts[0..])) return false;

    var storage: [4096]u8 = undefined;
    var arena = arena_mod.init(storage[0..]);
    const data = file_mod.readAll(&arena, path) catch return false;

    const expected = "seed=98\ncreature=eel\nzone=Z3\nphase=night\ntool=sonar\nA strike\nA decline\n";
    return eq(data, expected);
}

fn tRejectBadVerb() bool {
    const path = replayPath();
    file_mod.remove(path) catch {};
    file_mod.writeAll(path, "seed=98\ncreature=eel\nzone=Z3\nphase=night\ntool=sonar\nA punch\n") catch return false;

    var r: replay.Replay = undefined;
    return !replay.replayRead(path, &r);
}

fn sameState(a: *const def.GameState, b: *const def.GameState) bool {
    if (a.fight.outcome != b.fight.outcome) return false;
    if (a.fight.rng_state != b.fight.rng_state) return false;
    if (a.fight.hp != b.fight.hp) return false;
    if (a.fight.res != b.fight.res) return false;
    if (a.fight.hull != b.fight.hull) return false;
    if (a.log_n != b.log_n) return false;

    var i: usize = 0;
    while (i < def.MAX_LOG) : (i += 1) {
        if (a.log[i].class != b.log[i].class) return false;
        if (a.log[i].msg_id != b.log[i].msg_id) return false;
        if (a.log[i].a != b.log[i].a) return false;
        if (a.log[i].b != b.log[i].b) return false;
    }
    return true;
}

fn runStream(s: *def.GameState, acts: []const def.Action) void {
    s.exp.seed = 98;
    s.exp.fight_index = 0;
    var d = creatures.defAt(0);
    fight.startFightDef(s, 0, &d, creatures.RULES[0..]);

    var i: usize = 0;
    while (i < acts.len) : (i += 1) {
        fight.step(s, acts[i], &d, creatures.RULES[0..]);
    }
}

fn tDeterministicReplay() bool {
    const path = replayPath();
    file_mod.remove(path) catch {};
    const acts = [16]def.Action{
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
        def.Action{ .kind = def.ACT_RESTRAIN, .arg = 0 },
    };

    if (!replay.replayWrite(path, 98, "eel", "Z3", "night", "sonar", acts[0..])) return false;

    var r: replay.Replay = undefined;
    if (!replay.replayRead(path, &r)) return false;

    var a: def.GameState = undefined;
    var b: def.GameState = undefined;
    runStream(&a, replay.actionSlice(&r));
    runStream(&b, replay.actionSlice(&r));
    if (a.fight.actions == 0) return false;
    return sameState(&a, &b);
}

pub fn main() void {
    report("replay_round_trip_seed_headers_actions", tRoundTrip());
    report("replay_exact_v2_bytes", tExactBytes());
    report("replay_rejects_unknown_verb", tRejectBadVerb());
    report("replay_deterministic_outcome_log_rng", tDeterministicReplay());

    cleanupDefault();

    if (fails != 0) os.exit(1);
    io.write("replay_test PASS\n");
}
