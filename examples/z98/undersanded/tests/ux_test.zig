// ux_test.zig — UNDERSANDED M10.1 field status-line infrastructure driver.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/ux_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/ux_test"
//   "$OUT/ux_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const game = @import("../game.zig");
const nav = @import("../nav.zig");
const input = @import("../input.zig");

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

fn key(c: u8) input.Key {
    return input.Key{ .ch = c, .code = 0 };
}

fn fieldMsgZeroed(st: *const nav.NavState) bool {
    var i: usize = 0;
    while (i < st.field_msg.len) : (i += 1) {
        if (st.field_msg[i] != 0) return false;
    }
    return true;
}

fn tInitStateZeroesEveryField() bool {
    var st = nav.initState();
    if (st.armed != 0) return false;
    if (st.last != def.NAV_RESULT_NONE) return false;
    if (st.save_err_kind != 0) return false;
    if (st.help_page != nav.HELP_PAGE_NONE) return false;
    if (st.tip != nav.TIP_NONE) return false;
    if (st.journal_sel != 0) return false;
    if (st.boot_pending != 0) return false;
    if (st.field_msg_len != 0) return false;
    if (!fieldMsgZeroed(&st)) return false;

    nav.navSetFieldMsg(&st, "dirty");
    var fresh = nav.initState();
    if (fresh.field_msg_len != 0) return false;
    if (!fieldMsgZeroed(&fresh)) return false;
    return true;
}

fn tFieldMsgClearedOnNextKey() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.screen = def.NAV_DOCK;
    var st = nav.initState();

    nav.navSetFieldMsg(&st, "Killed Mystic Eel - Secured: Shell Chip.");
    if (st.field_msg_len == 0) return false;

    _ = nav.navStep(&g, &st, key('x'));
    if (st.field_msg_len != 0) return false;
    if (!fieldMsgZeroed(&st)) return false;

    var out: [8]u8 = undefined;
    const line = nav.navResultLine(&g, &st, out[0..]);
    if (line.len != 0) return false;

    var after = nav.initState();
    after.last = 0;
    nav.navSetFieldMsg(&after, "one action");
    _ = nav.navStep(&g, &after, key('x'));
    if (after.field_msg_len != 0) return false;
    if (after.last >= 0) return false;
    return true;
}

fn tNavResultLinePrefersFieldMsg() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    var st = nav.initState();
    var out: [8]u8 = undefined;

    st.last = 0;
    const dock_line = nav.navResultLine(&g, &st, out[0..]);
    if (dock_line.len == 0) return false;

    nav.navSetFieldMsg(&st, "Departed to Z2 - travel 1 out, 1 back (+1 depart action).");
    const field_line = nav.navResultLine(&g, &st, out[0..]);
    if (field_line.len != st.field_msg_len) return false;
    var i: usize = 0;
    while (i < field_line.len) : (i += 1) {
        if (field_line[i] != st.field_msg[i]) return false;
    }

    nav.navClearFieldMsg(&st);
    const again = nav.navResultLine(&g, &st, out[0..]);
    if (again.len != dock_line.len) return false;
    i = 0;
    while (i < again.len) : (i += 1) {
        if (again[i] != dock_line[i]) return false;
    }
    return true;
}

fn tFieldMsgDoesNotChangePhaseOrRng() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    game.startFight(&g, 0);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.world.field_phases = 7;
    g.world.cycle = 3;
    g.world.phase = 1;
    g.fight.rng_state = 0x12345678;
    g.world.rng_state = 0x9abcdef0;

    const phases = g.world.field_phases;
    const cycle = g.world.cycle;
    const phase = g.world.phase;
    const fight_rng = g.fight.rng_state;
    const world_rng = g.world.rng_state;
    const hp = g.fight.hp;
    const res = g.fight.res;
    const hull = g.fight.hull;

    var st = nav.initState();
    nav.navSetFieldMsg(&st, "Rested at the node: +30 Hull.");
    nav.navSetFieldMsgInt(&st, "Rested at dock: +", 30, " Hull.");
    var out: [16]u8 = undefined;
    _ = nav.navResultLine(&g, &st, out[0..]);
    nav.navClearFieldMsg(&st);

    if (g.world.field_phases != phases) return false;
    if (g.world.cycle != cycle) return false;
    if (g.world.phase != phase) return false;
    if (g.fight.rng_state != fight_rng) return false;
    if (g.world.rng_state != world_rng) return false;
    if (g.fight.hp != hp) return false;
    if (g.fight.res != res) return false;
    if (g.fight.hull != hull) return false;
    return true;
}

pub fn main() void {
    report("init_state_zeroes_every_field", tInitStateZeroesEveryField());
    report("field_msg_cleared_on_next_key", tFieldMsgClearedOnNextKey());
    report("nav_result_line_prefers_field_msg", tNavResultLinePrefersFieldMsg());
    report("field_msg_does_not_change_phase_or_rng", tFieldMsgDoesNotChangePhaseOrRng());

    if (fails != 0) os.exit(1);
    io.write("ux_test PASS\n");
}
