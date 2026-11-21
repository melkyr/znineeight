// undtool.zig — UNDERSANDED console tool dispatcher (spec §26).
//
// main_console.zig routes any argv element beginning with `--` here before the
// playable console; tool paths never touch sample.txt or a fight UI. M3 Task 2
// owns `--sim N --creature <token> --seed S`; later tasks extend this
// dispatcher with --replay, --test-rules, --dump-grid, --dump-defs and
// --save-roundtrip.
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
const nav = @import("nav.zig");
const journal = @import("journal.zig");
const save_ux = @import("save_ux.zig");
const fight_console = @import("fight_console.zig");
const paths = @import("paths.zig");
const file_mod = @import("std_file");
const arena_mod = @import("std_arena");
const buf_mod = @import("std_buf");
const data = @import("data.zig");
const content_boot = @import("content_boot.zig");
const persist = @import("persist.zig");
const text_scan = @import("text_scan.zig");
const fallback_emit = @import("fallback_emit.zig");
const validate_assets = @import("validate_assets.zig");

const TokenRow = struct { name: []const u8, index: i32 };

// Pinned seed for the deterministic --dump-grid fight frame (never CLI seed0).
const DUMP_SEED: u32 = 98;

// --dump-defs uses its own permanent arena and never installs the override.
var g_dump_arena_buf: [256 * 1024]u8 = undefined;

// Tool paths load data.z98 beside the exe when present; failure keeps fallback.
var g_content_arena_buf: [256 * 1024]u8 = undefined;

// --save-roundtrip keeps its own arena: the original image and the re-saved
// temp image must both stay intact for the byte compare.
var g_rt_arena_buf: [256 * 1024]u8 = undefined;

// --emit-fallback writes through a separate arena so the loaded content arena
// stays untouched for the deterministic source dump.
var g_emit_arena_buf: [256 * 1024]u8 = undefined;

// --validate-assets owns its manifest arena and must not install content.
var g_validate_arena_buf: [64 * 1024]u8 = undefined;

fn tryLoadContent() void {
    var dir_buf: [512]u8 = undefined;
    const dir = paths.resolveDataDir(dir_buf[0..]);
    var arena = arena_mod.init(g_content_arena_buf[0..]);
    _ = content_boot.loadFromDir(&arena, &data.g_tables, dir);
}

// Load data.z98 (never the compiled fallback) and write the checked-in Z98
// module. 0 = written, 2 = load/write failure.
fn emitFallback(outdir: []const u8) i32 {
    var dir_buf: [512]u8 = undefined;
    const dir = paths.resolveDataDir(dir_buf[0..]);
    var load_arena = arena_mod.init(g_content_arena_buf[0..]);
    const boot = content_boot.loadFromDir(&load_arena, &data.g_tables, dir);
    if (boot.result != .Loaded) {
        fail("undtool: --emit-fallback cannot load data.z98");
        return 2;
    }

    var arena = arena_mod.init(g_emit_arena_buf[0..]);
    var out = buf_mod.initCapacity(&arena, 128 * 1024) catch {
        fail("undtool: --emit-fallback out of memory");
        return 2;
    };
    fallback_emit.emit(&data.g_tables, &out);

    var path_buf: [600]u8 = undefined;
    const path = paths.join(outdir, "fallback_rows.zig", path_buf[0..]) orelse {
        fail("undtool: --emit-fallback output path too long");
        return 2;
    };
    file_mod.writeAll(path, buf_mod.slice(&out)) catch {
        fail("undtool: --emit-fallback write failed");
        return 2;
    };
    return 0;
}

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

// Tool tokens address loaded def indexes; a partial data.z98 can carry fewer
// rows than the compiled-in fallback, so reject before defAt can panic.
fn tokenDefIndex(tok: []const u8) ?i32 {
    const index = tokenIndex(tok) orelse return null;
    if (index < 0 or index >= creatures.defCount()) return null;
    return index;
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
    fight.startFightDef(&s, def_index, &d, creatures.rules());
    fight.step(&s, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 }, &d, creatures.rules());
    var sc: render.Screen = undefined;
    render.renderFrame(&s, &d, &sc);
    return render.dump(&sc, out);
}

// --dump-grid payload for the fixed non-fight screens. The pinned state is a
// zeroed GameState with the canonical zero World overlaid (Hull 100, Coins 0,
// all boat tiers 0, no creatures seen). Returns null for an unknown id.
pub fn dumpFixedScreen(screen_id: []const u8, out: []u8) ?[]const u8 {
    var s: def.GameState = undefined;
    sim.zeroState(&s);
    game.zeroWorld(&s.world);
    s.fight.def_index = def.NO_FIGHT;
    s.fight.outcome = def.OUT_ONGOING;
    s.exp.seed = DUMP_SEED;

    var sc: render.Screen = undefined;
    if (eq(screen_id, "dock")) {
        var v: render.View = undefined;
        nav.prepareDock(&s, &v);
        render.renderDock(&v, &sc);
    } else if (eq(screen_id, "map")) {
        var v: render.View = undefined;
        nav.prepareMap(&s, &v);
        render.renderMap(&v, &sc);
    } else if (eq(screen_id, "node")) {
        var v: render.View = undefined;
        nav.prepareNode(&s, &v);
        render.renderNode(&v, &sc);
    } else if (eq(screen_id, "subdue") or eq(screen_id, "settle")) {
        // Synthetic pending Subdue: loot/log/hull already resolved, as after
        // postFight. `subdue` is the Continue-only intro; `settle` is 1/2.
        if (eq(screen_id, "subdue")) {
            s.screen = def.NAV_SUBDUE_INTRO;
        } else {
            s.screen = def.NAV_SETTLE;
        }
        s.exp.active = 1;
        s.exp.zone = 1;
        s.fight.def_index = 0;
        s.fight.outcome = def.OUT_SUBDUE;
        s.fight.hull = s.world.hull;
        fight.log(&s, def.CLS_SECURED, def.MSG_SECURED, 0, def.OUT_SUBDUE);
        var v: render.View = undefined;
        nav.prepareNode(&s, &v);
        render.renderNode(&v, &sc);
    } else if (eq(screen_id, "lore")) {
        render.renderLore(save_ux.manualPageOne(), &sc);
    } else if (eq(screen_id, "menu")) {
        render.renderMenu(&sc);
    } else if (eq(screen_id, "help")) {
        // Canonical `?` page from the dock (def.NAV_DOCK = 10 -> manual.1).
        render.renderHelp(journal.helpPage(def.NAV_DOCK) orelse "(manual text unavailable)", &sc);
    } else if (eq(screen_id, "journal")) {
        // Fresh install: every entry is still "- unrecorded -".
        var v: render.View = undefined;
        nav.prepareJournal(&s, 0, &v);
        render.renderJournal(&v, &sc);
    } else {
        return null;
    }
    return render.dump(&sc, out);
}

// ---- replay --------------------------------------------------------------
//
// The v2 stream is a header plus one verb per action (spec §28). This replays
// it through the same gameStep path the sim/UI use, then serializes the exact
// fight log as `<class>:<msg_id>:<a>:<b>;` per entry (the fight_test format).

fn appendLog(buf: []u8, pos: *usize, s: *const def.GameState) void {
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        const e = s.log[@intCast(usize, i)];
        text_scan.appendInt(buf, pos, @intCast(i64, e.class));
        text_scan.appendText(buf, pos, ":");
        text_scan.appendInt(buf, pos, @intCast(i64, e.msg_id));
        text_scan.appendText(buf, pos, ":");
        text_scan.appendInt(buf, pos, @intCast(i64, e.a));
        text_scan.appendText(buf, pos, ":");
        text_scan.appendInt(buf, pos, @intCast(i64, e.b));
        text_scan.appendText(buf, pos, ";");
    }
}

// Read `path`, replay its action stream deterministically, and write the one
// report line (without the trailing newline) into `out`. Returns null when the
// file cannot be read/parsed or its creature token is unknown.
pub fn replayLine(path: []const u8, out: []u8) ?[]const u8 {
    var r: replay.Replay = undefined;
    if (!replay.replayRead(path, &r)) return null;

    const index = tokenDefIndex(replay.creatureText(&r)) orelse return null;

    var s: def.GameState = undefined;
    sim.zeroState(&s);
    s.exp.seed = r.seed;

    var d = creatures.defAt(index);
    fight.startFightDef(&s, index, &d, creatures.rules());

    var applied: i32 = 0;
    const acts = replay.actionSlice(&r);
    var i: usize = 0;
    while (i < acts.len) : (i += 1) {
        if (s.fight.outcome != def.OUT_ONGOING) break;
        game.gameStep(&s, acts[i]);
        applied += 1;
    }

    var pos: usize = 0;
    text_scan.appendText(out, &pos, "replay outcome=");
    text_scan.appendInt(out, &pos, @intCast(i64, s.fight.outcome));
    text_scan.appendText(out, &pos, " actions=");
    text_scan.appendInt(out, &pos, @intCast(i64, applied));
    text_scan.appendText(out, &pos, " rng=");
    text_scan.appendUint(out, &pos, @intCast(u64, s.fight.rng_state));
    text_scan.appendText(out, &pos, " log=");
    appendLog(out, &pos, &s);
    return out[0..pos];
}

fn bytesEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn withSuffix(path: []const u8, suffix: []const u8, out: []u8) ?[]const u8 {
    if (path.len + suffix.len > out.len) return null;
    var i: usize = 0;
    while (i < path.len) : (i += 1) out[i] = path[i];
    var j: usize = 0;
    while (j < suffix.len) : (j += 1) out[path.len + j] = suffix[j];
    return out[0 .. path.len + suffix.len];
}

fn asciiLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn eqNoCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (asciiLower(a[i]) != asciiLower(b[i])) return false;
    }
    return true;
}

fn baseName(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path[i + 1 ..];
    }
    return path;
}

// Directory part of a path (no trailing separator); "" for a bare filename.
fn dirOf(path: []const u8, out: []u8) ?[]const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') {
            if (i > out.len) return null;
            var j: usize = 0;
            while (j < i) : (j += 1) out[j] = path[j];
            return out[0..i];
        }
    }
    return out[0..0];
}

fn reservedSaveName(path: []const u8) bool {
    const b = baseName(path);
    if (eqNoCase(b, "save.tmp")) return true;
    if (eqNoCase(b, "save.bak")) return true;
    return false;
}

fn removeChecked(path: []const u8) bool {
    if (!file_mod.exists(path)) return true;
    file_mod.remove(path) catch return false;
    return true;
}

// --save-roundtrip: load, re-save to a distinct .rt path, byte-compare. Never
// installs content (def.content_override stays null -> content version 2), never
// writes the original path and never touches the sibling save.tmp/save.bak.
// 0 = identical, 1 = differs, 2 = bad input.
fn saveRoundTrip(path: []const u8) i32 {
    if (reservedSaveName(path)) {
        fail("undtool: --save-roundtrip refuses save.tmp/save.bak");
        return 2;
    }
    if (!file_mod.exists(path)) {
        fail("undtool: --save-roundtrip cannot read save file");
        return 2;
    }

    var arena = arena_mod.init(g_rt_arena_buf[0..]);
    const before = file_mod.readAll(&arena, path) catch {
        fail("undtool: --save-roundtrip cannot read save file");
        return 2;
    };

    var w: def.World = undefined;
    var exp: def.Expedition = undefined;
    persist.saveRead(path, &w, &exp) catch {
        fail("undtool: --save-roundtrip cannot read save file");
        return 2;
    };

    var tmp_buf: [4096]u8 = undefined;
    const tmp = withSuffix(path, ".rt", tmp_buf[0..]) orelse {
        fail("undtool: --save-roundtrip path too long");
        return 2;
    };
    if (!removeChecked(tmp)) {
        fail("undtool: --save-roundtrip cannot remove re-save file");
        return 2;
    }
    persist.saveWriteDirect(tmp, &w, &exp) catch {
        _ = removeChecked(tmp);
        fail("undtool: --save-roundtrip cannot re-save save file");
        return 2;
    };

    const after = file_mod.readAll(&arena, tmp) catch {
        _ = removeChecked(tmp);
        fail("undtool: --save-roundtrip cannot read re-saved file");
        return 2;
    };
    if (!removeChecked(tmp)) {
        fail("undtool: --save-roundtrip cannot remove re-save file");
        return 2;
    }

    if (bytesEq(before, after)) return 0;
    return 1;
}

pub fn run(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);

    var have_sim = false;
    var have_creature = false;
    var have_seed = false;
    var have_test_rules = false;
    var have_replay = false;
    var have_dump_grid = false;
    var have_dump_defs = false;
    var have_save_roundtrip = false;
    var have_emit_fallback = false;
    var have_validate_assets = false;
    var have_screen = false;
    var have_play = false;
    var have_fight = false;
    var have_hull = false;
    var n_fights: i32 = 0;
    var seed0: u32 = 0;
    var hull: i32 = 100;
    var token: []const u8 = "";
    var replay_path: []const u8 = "";
    var dump_path: []const u8 = "";
    var defs_path: []const u8 = "";
    var roundtrip_path: []const u8 = "";
    var fallback_dir: []const u8 = "";
    var validate_path: []const u8 = "";
    var validate_assets_dir: []const u8 = "";
    var screen_id: []const u8 = "";

    const nargs = os.argc();
    var i: usize = 0;
    while (i < nargs) : (i += 1) {
        const a = os.argv(i);
        if (eq(a, "--test-rules")) {
            have_test_rules = true;
        } else if (eq(a, "--play")) {
            have_play = true;
        } else if (eq(a, "--fight")) {
            have_fight = true;
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
        } else if (eq(a, "--dump-defs")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --dump-defs needs a file path");
                return;
            }
            defs_path = os.argv(i);
            have_dump_defs = true;
        } else if (eq(a, "--emit-fallback")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --emit-fallback needs an output directory");
                return;
            }
            fallback_dir = os.argv(i);
            have_emit_fallback = true;
        } else if (eq(a, "--save-roundtrip")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --save-roundtrip needs a file path");
                return;
            }
            roundtrip_path = os.argv(i);
            have_save_roundtrip = true;
        } else if (eq(a, "--validate-assets")) {
            i += 1;
            if (i >= nargs) {
                fail("undtool: --validate-assets needs a manifest path");
                return;
            }
            validate_path = os.argv(i);
            have_validate_assets = true;
            if (i + 1 < nargs and !startsFlag(os.argv(i + 1))) {
                i += 1;
                validate_assets_dir = os.argv(i);
                if (i + 1 < nargs and !startsFlag(os.argv(i + 1))) {
                    fail("undtool: --validate-assets takes at most a manifest and assets directory");
                    return;
                }
            }
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
            have_hull = true;
        } else if (startsFlag(a)) {
            fail("undtool: unknown flag");
            return;
        }
    }

    // Every mode except --dump-defs, --save-roundtrip, --emit-fallback and
    // --validate-assets runs with data.z98 beside the exe when it is there; a
    // bad file never fails the tool (fallback stays installed). Those modes
    // handle content themselves and must not install an override as a side
    // effect.
    if (!have_dump_defs and !have_save_roundtrip and !have_emit_fallback and !have_validate_assets) tryLoadContent();

    // --validate-assets is exclusive with every other mode. Check this before
    // the emit branch so a combined invocation cannot install content or write
    // fallback_rows.zig.
    if (have_validate_assets) {
        if (have_test_rules or have_replay or have_dump_grid or have_dump_defs or
            have_save_roundtrip or have_emit_fallback or have_screen or have_sim or
            have_creature or have_seed or have_hull or have_play or have_fight)
        {
            fail("undtool: --validate-assets cannot be combined with other flags");
            return;
        }
    }

    if (have_emit_fallback) {
        os.exit(emitFallback(fallback_dir));
        return;
    }

    // Interactive play modes are exclusive: neither combines with the other nor
    // with any tool flag.
    if (have_play or have_fight) {
        if (have_play and have_fight) {
            fail("undtool: --play and --fight are mutually exclusive");
            return;
        }
        if (have_test_rules or have_replay or have_dump_grid or have_dump_defs or
            have_save_roundtrip or have_emit_fallback or have_validate_assets or
            have_screen or have_sim or have_creature or have_seed or have_hull)
        {
            fail("undtool: --play/--fight cannot be combined with tool flags");
            return;
        }
        if (have_play) {
            var s: def.GameState = undefined;
            game.newGame(&s);
            nav.navRun(&s);
        } else {
            fight_console.run();
        }
        os.exit(0);
        return;
    }

    if (have_validate_assets) {
        var arena = arena_mod.init(g_validate_arena_buf[0..]);
        const man = file_mod.readAll(&arena, validate_path) catch {
            fail("undtool: --validate-assets cannot read manifest");
            return;
        };
        var dir_buf: [512]u8 = undefined;
        var dir = validate_assets_dir;
        if (dir.len == 0) {
            dir = dirOf(validate_path, dir_buf[0..]) orelse {
                fail("undtool: --validate-assets manifest path too long");
                return;
            };
        }
        const err = validate_assets.validateManifest(man, dir);
        if (err != .Ok) {
            var msg: [200]u8 = undefined;
            var p: usize = 0;
            text_scan.appendText(msg[0..], &p, "undtool: --validate-assets invalid: ");
            text_scan.appendText(msg[0..], &p, validate_assets.errorText(err));
            fail(msg[0..p]);
            return;
        }
        os.exit(0);
        return;
    }

    if (have_save_roundtrip) {
        os.exit(saveRoundTrip(roundtrip_path));
        return;
    }

    if (have_test_rules) {
        os.exit(ruletest.testRules());
        return;
    }

    if (have_dump_defs) {
        var arena = arena_mod.init(g_dump_arena_buf[0..]);
        var t: def.Tables = undefined;
        data.loadFile(&arena, defs_path, &t) catch {
            fail("undtool: --dump-defs cannot read or parse data file");
            return;
        };
        var out = buf_mod.initCapacity(&arena, 64 * 1024) catch {
            fail("undtool: --dump-defs out of memory");
            return;
        };
        data.dumpDefs(&t, &out);
        io.write(buf_mod.slice(&out));
        os.exit(0);
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
        var buf: [8192]u8 = undefined;
        var text: []const u8 = undefined;
        if (eq(screen_id, "fight")) {
            var dump_index: i32 = 0;
            if (have_creature) {
                dump_index = tokenDefIndex(token) orelse {
                    fail("undtool: unknown --creature token");
                    return;
                };
            }
            text = dumpFightFrame(dump_index, DUMP_SEED, buf[0..]);
        } else {
            text = dumpFixedScreen(screen_id, buf[0..]) orelse {
                fail("undtool: unknown --screen id");
                return;
            };
        }
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

    const index = tokenDefIndex(token) orelse {
        fail("undtool: unknown --creature token");
        return;
    };

    const r = sim.runSim(index, n_fights, seed0, hull);

    io.write("defs actions=steps ascent=hull0 bars=switches prompt=modal\n");
    writeReport(token, &r);
}
