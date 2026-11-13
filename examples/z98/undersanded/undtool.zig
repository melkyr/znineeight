// undtool.zig — UNDERSANDED console tool dispatcher (spec §26).
//
// main_console.zig routes any argv element beginning with `--` here before the
// playable console; tool paths never touch sample.txt or a fight UI. M3 Task 2
// owns `--sim N --creature <token> --seed S`; later tasks extend this
// dispatcher with --replay, --test-rules and --dump-grid.
//
// Token table (tooling only; CreatureDef has no name field):
//   eel -> 0, electric_eel -> 1, steel_tuna -> 2,
//   anemoniacus -> 3, freezing_perch -> 4
// Invalid token/flag prints to stderr and exits 2.

const io = @import("std_io.zig");
const os = @import("std_os.zig");
const parse = @import("std_parse");
const sim = @import("sim.zig");
const ruletest = @import("ruletest.zig");
const replay = @import("replay.zig");
const def = @import("def.zig");
const fight = @import("fight.zig");
const game = @import("game.zig");
const creatures = @import("creatures_t1.zig");
const render = @import("render_term.zig");
const file_mod = @import("std_file");

const TokenRow = struct { name: []const u8, index: i32 };

// Pinned seed for the deterministic --dump-grid fight frame (never CLI seed0).
const DUMP_SEED: u32 = 98;

const TOKEN_ROWS = [_]TokenRow{
    TokenRow{ .name = "eel", .index = 0 },
    TokenRow{ .name = "electric_eel", .index = 1 },
    TokenRow{ .name = "steel_tuna", .index = 2 },
    TokenRow{ .name = "anemoniacus", .index = 3 },
    TokenRow{ .name = "freezing_perch", .index = 4 },
};

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn startsFlag(a: []const u8) bool {
    if (a.len < 2) return false;
    return a[0] == '-' and a[1] == '-';
}

fn tokenIndex(tok: []const u8) ?i32 {
    var i: usize = 0;
    while (i < TOKEN_ROWS.len) : (i += 1) {
        if (eq(TOKEN_ROWS[i].name, tok)) return TOKEN_ROWS[i].index;
    }
    return null;
}

fn fail(msg: []const u8) void {
    @stderrWrite(msg.ptr, msg.len);
    @stderrWrite("\n", 1);
    os.exit(2);
}

fn writeReport(token: []const u8, r: *const sim.SimReport) void {
    io.write("sim creature=");
    io.write(token);
    io.write(" fights=");
    io.printInt(r.fights);
    io.write(" actions_avg=");
    io.printInt(sim.actionsAvg(r));
    io.write(" rare_actions_pm=");
    io.printInt(sim.rareActionsPm(r));
    io.write(" ascent_pm=");
    io.printInt(sim.ascentPm(r));
    io.write(" bar_switch_pct=");
    io.printInt(sim.barSwitchPct(r));
    io.write(" surge_avg_pm=");
    io.printInt(sim.surgeAvgPm(r));
    io.write(" prompts=");
    io.printInt(r.prompts);
    io.write(" outcomes=");
    io.printInt(r.subdue);
    io.write(":");
    io.printInt(r.kill);
    io.write(":");
    io.printInt(r.overkill);
    io.write(":");
    io.printInt(r.fled);
    io.write(":");
    io.printInt(r.ascents);
    io.write("\n");
}

// --dump-grid payload for `--screen fight`: a scripted, fixed-seed FightState
// (def index 0, one Strike so the log has a bar/log line) rendered by
// render_term and returned as the trimmed row-major dump. The caller writes the
// returned slice; this module never touches std_gfx (gfxDumpGrid covers only
// the gfx memory surface, which Task 5 owns).
pub fn dumpFightFrame(def_index: i32, seed: u32, out: []u8) []const u8 {
    var s: def.GameState = undefined;
    sim.zeroState(&s);
    s.exp.seed = seed;
    s.exp.fight_index = 0;
    var d = creatures.defAt(def_index);
    fight.startFightDef(&s, def_index, &d, creatures.RULES[0..]);
    fight.step(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, creatures.RULES[0..]);
    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);
    return render.dump(&sc, out);
}

// ---- replay --------------------------------------------------------------
//
// The v2 stream is a header plus one verb per action (spec §28). This replays
// it through the same gameStep path the sim/UI use, then serializes the exact
// fight log as `<class>:<msg_id>:<a>:<b>;` per entry (the fight_test format).

fn appendStr(buf: []u8, pos: *usize, text: []const u8) void {
    var i: usize = 0;
    while (i < text.len and pos.* < buf.len) : (i += 1) {
        buf[pos.*] = text[i];
        pos.* += 1;
    }
}

fn appendInt(buf: []u8, pos: *usize, v: i32) void {
    if (pos.* >= buf.len) return;
    if (v == 0) {
        buf[pos.*] = '0';
        pos.* += 1;
        return;
    }
    var n: u32 = 0;
    var neg = false;
    if (v < 0) {
        neg = true;
        n = @intCast(u32, 0 - v);
    } else {
        n = @intCast(u32, v);
    }
    var tmp: [16]u8 = undefined;
    var t: usize = 0;
    while (n > 0) {
        tmp[t] = @intCast(u8, '0' + @intCast(i32, n % 10));
        n = n / 10;
        t += 1;
    }
    if (neg and pos.* < buf.len) {
        buf[pos.*] = '-';
        pos.* += 1;
    }
    while (t > 0 and pos.* < buf.len) {
        t -= 1;
        buf[pos.*] = tmp[t];
        pos.* += 1;
    }
}

fn appendUint(buf: []u8, pos: *usize, v: u32) void {
    if (pos.* >= buf.len) return;
    if (v == 0) {
        buf[pos.*] = '0';
        pos.* += 1;
        return;
    }
    var n: u32 = v;
    var tmp: [16]u8 = undefined;
    var t: usize = 0;
    while (n > 0) {
        tmp[t] = @intCast(u8, '0' + @intCast(i32, n % 10));
        n = n / 10;
        t += 1;
    }
    while (t > 0 and pos.* < buf.len) {
        t -= 1;
        buf[pos.*] = tmp[t];
        pos.* += 1;
    }
}

fn appendLog(buf: []u8, pos: *usize, s: *const def.GameState) void {
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        const e = s.log[@intCast(usize, i)];
        appendInt(buf, pos, e.class);
        appendStr(buf, pos, ":");
        appendInt(buf, pos, e.msg_id);
        appendStr(buf, pos, ":");
        appendInt(buf, pos, e.a);
        appendStr(buf, pos, ":");
        appendInt(buf, pos, e.b);
        appendStr(buf, pos, ";");
    }
}

// Read `path`, replay its action stream deterministically, and write the one
// report line (without the trailing newline) into `out`. Returns null when the
// file cannot be read/parsed or its creature token is unknown.
pub fn replayLine(path: []const u8, out: []u8) ?[]const u8 {
    var r: replay.Replay = undefined;
    if (!replay.replayRead(path, &r)) return null;

    const index = tokenIndex(replay.creatureText(&r)) orelse return null;

    var s: def.GameState = undefined;
    sim.zeroState(&s);
    s.exp.seed = r.seed;

    var d = creatures.defAt(index);
    fight.startFightDef(&s, index, &d, creatures.RULES[0..]);

    var applied: i32 = 0;
    const acts = replay.actionSlice(&r);
    var i: usize = 0;
    while (i < acts.len) : (i += 1) {
        if (s.fight.outcome != def.OUT_ONGOING) break;
        game.gameStep(&s, acts[i]);
        applied += 1;
    }

    var pos: usize = 0;
    appendStr(out, &pos, "replay outcome=");
    appendInt(out, &pos, s.fight.outcome);
    appendStr(out, &pos, " actions=");
    appendInt(out, &pos, applied);
    appendStr(out, &pos, " rng=");
    appendUint(out, &pos, s.fight.rng_state);
    appendStr(out, &pos, " log=");
    appendLog(out, &pos, &s);
    return out[0..pos];
}

pub fn run(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);

    var have_sim = false;
    var have_creature = false;
    var have_seed = false;
    var have_test_rules = false;
    var have_replay = false;
    var have_dump_grid = false;
    var have_screen = false;
    var n_fights: i32 = 0;
    var seed0: u32 = 0;
    var hull: i32 = 100;
    var token: []const u8 = "";
    var replay_path: []const u8 = "";
    var dump_path: []const u8 = "";
    var screen_id: []const u8 = "";

    const nargs = os.argc();
    var i: usize = 0;
    while (i < nargs) : (i += 1) {
        const a = os.argv(i);
        if (eq(a, "--test-rules")) {
            have_test_rules = true;
        } else if (eq(a, "--replay")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --replay needs a file path");
                return;
            }
            replay_path = os.argv(i);
            have_replay = true;
        } else if (eq(a, "--dump-grid")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --dump-grid needs a file path");
                return;
            }
            dump_path = os.argv(i);
            have_dump_grid = true;
        } else if (eq(a, "--screen")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --screen needs an id");
                return;
            }
            screen_id = os.argv(i);
            have_screen = true;
        } else if (eq(a, "--sim")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --sim needs a fight count");
                return;
            }
            n_fights = parse.parseInt(os.argv(i)) orelse {
                fail("undtool: --sim needs an integer fight count");
                return;
            };
            have_sim = true;
        } else if (eq(a, "--creature")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --creature needs a token");
                return;
            }
            token = os.argv(i);
            have_creature = true;
        } else if (eq(a, "--seed")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --seed needs an integer");
                return;
            }
            seed0 = parse.parseUint(os.argv(i)) orelse {
                fail("undtool: --seed needs a non-negative integer");
                return;
            };
            have_seed = true;
        } else if (eq(a, "--hull")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --hull needs an integer");
                return;
            }
            hull = parse.parseInt(os.argv(i)) orelse {
                fail("undtool: --hull needs an integer");
                return;
            };
            if (hull <= 0) {
                fail("undtool: --hull must be greater than 0");
                return;
            }
        } else if (startsFlag(a)) {
            fail("undtool: unknown flag");
            return;
        }
    }

    if (have_test_rules) {
        os.exit(ruletest.testRules());
        return;
    }

    if (have_replay) {
        var buf: [8192]u8 = undefined;
        const line = replayLine(replay_path, buf[0..]) orelse {
            fail("undtool: --replay cannot read or parse replay file");
            return;
        };
        io.write(line);
        io.write("\n");
        os.exit(0);
        return;
    }

    if (have_dump_grid) {
        if (!have_screen) {
            fail("undtool: --dump-grid requires --screen");
            return;
        }
        if (!eq(screen_id, "fight")) {
            fail("undtool: unknown --screen id");
            return;
        }
        var dump_index: i32 = 0;
        if (have_creature) {
            dump_index = tokenIndex(token) orelse {
                fail("undtool: unknown --creature token");
                return;
            };
        }
        var buf: [8192]u8 = undefined;
        const text = dumpFightFrame(dump_index, DUMP_SEED, buf[0..]);
        file_mod.writeAll(dump_path, text) catch {
            fail("undtool: --dump-grid write failed");
            return;
        };
        os.exit(0);
        return;
    }

    if (!have_sim) {
        fail("undtool: expected --sim");
        return;
    }
    if (!have_creature) {
        fail("undtool: --sim requires --creature");
        return;
    }
    if (!have_seed) {
        fail("undtool: --sim requires --seed");
        return;
    }
    if (n_fights <= 0) {
        fail("undtool: --sim N must be greater than 0");
        return;
    }

    const index = tokenIndex(token) orelse {
        fail("undtool: unknown --creature token");
        return;
    };

    const r = sim.runSim(index, n_fights, seed0, hull);

    io.write("defs actions=steps ascent=hull0 bars=switches prompt=modal\n");
    writeReport(token, &r);
}
