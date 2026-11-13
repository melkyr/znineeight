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

const TokenRow = struct { name: []const u8, index: i32 };

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
    io.write(" rare_actions_avg=");
    io.printInt(sim.rareActionsAvg(r));
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

pub fn run(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);

    var have_sim = false;
    var have_creature = false;
    var have_seed = false;
    var n_fights: i32 = 0;
    var seed0: u32 = 0;
    var token: []const u8 = "";

    const nargs = os.argc();
    var i: usize = 0;
    while (i < nargs) : (i += 1) {
        const a = os.argv(i);
        if (eq(a, "--sim")) {
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
        } else if (startsFlag(a)) {
            fail("undtool: unknown flag");
            return;
        }
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

    const r = sim.runSim(index, n_fights, seed0);

    io.write("defs actions=steps ascent=hull0 bars=switches prompt=modal\n");
    writeReport(token, &r);
}
