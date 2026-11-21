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
const expedition = @import("../expedition.zig");
const creatures = @import("../creatures_t1.zig");
const world = @import("../world.zig");
const text_scan = @import("../text_scan.zig");
const render_text = @import("../render_text.zig");
const std_mem = @import("std_mem.zig");

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

fn msgZeroed(buf: []const u8) bool {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        if (buf[i] != 0) return false;
    }
    return true;
}

const Snap = struct {
    phases: i32, cycle: i32, phase: i32, fight_rng: u32, world_rng: u32,
    hp: i32, res: i32, hull: i32, world_hull: i32, money: i32, hold: i32,
};

fn snap(g: *const def.GameState) Snap {
    return Snap{ .phases = g.world.field_phases, .cycle = g.world.cycle,
        .phase = g.world.phase, .fight_rng = g.fight.rng_state,
        .world_rng = g.world.rng_state, .hp = g.fight.hp, .res = g.fight.res,
        .hull = g.fight.hull, .world_hull = g.world.hull,
        .money = g.world.money, .hold = g.exp.hold[1] };
}

fn snapSame(g: *const def.GameState, s: Snap) bool {
    return g.world.field_phases == s.phases and g.world.cycle == s.cycle
        and g.world.phase == s.phase and g.fight.rng_state == s.fight_rng
        and g.world.rng_state == s.world_rng and g.fight.hp == s.hp
        and g.fight.res == s.res and g.fight.hull == s.hull
        and g.world.hull == s.world_hull and g.world.money == s.money
        and g.exp.hold[1] == s.hold;
}

fn logHas(g: *const def.GameState, id: i32) bool {
    var i: i32 = 0;
    while (i < g.log_n) : (i += 1) {
        if (g.log[@intCast(usize, i)].msg_id == id) return true;
    }
    return false;
}

fn logText(g: *const def.GameState, id: i32, want: []const u8) bool {
    var i: i32 = 0;
    while (i < g.log_n) : (i += 1) {
        if (g.log[@intCast(usize, i)].msg_id != id) continue;
        var d = creatures.defAt(g.fight.def_index);
        var buf: [128]u8 = undefined;
        return lineIs(render_text.msgLine(g.log[@intCast(usize, i)], &d, buf[0..]), want);
    }
    return false;
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
    if (st.field_msg_len != 0 or st.dock_msg_len != 0) return false;
    if (!msgZeroed(st.field_msg[0..]) or !msgZeroed(st.dock_msg[0..])) return false;

    nav.navSetFieldMsg(&st, "dirty");
    var fresh = nav.initState();
    if (fresh.field_msg_len != 0 or fresh.dock_msg_len != 0) return false;
    if (!msgZeroed(fresh.field_msg[0..]) or !msgZeroed(fresh.dock_msg[0..])) return false;
    return true;
}

fn tFieldMsgClearedOnNextKey() bool {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.screen = def.NAV_DOCK;
    var st = nav.initState();
    nav.navSetFieldMsg(&st, "Killed Mystic Eel.");
    if (st.field_msg_len == 0) return false;
    _ = nav.navStep(&g, &st, key('x'));
    if (st.field_msg_len != 0) return false;
    if (!msgZeroed(st.field_msg[0..])) return false;
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
    const before = snap(&g);

    var st = nav.initState();
    nav.navSetFieldMsg(&st, "Rested at the node: +30 Hull.");
    nav.navSetFieldMsgInt(&st, "Rested at dock: +", 30, " Hull.");
    var out: [16]u8 = undefined;
    _ = nav.navResultLine(&g, &st, out[0..]);
    nav.navClearFieldMsg(&st);
    return snapSame(&g, before);
}

fn pendingState(screen: i32) def.GameState {
    var g: def.GameState = undefined;
    game.newGame(&g);
    g.exp.active = 1;
    g.exp.zone = 1;
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_SUBDUE;
    g.fight.hull = 80;
    g.world.hull = 80;
    g.screen = screen;
    return g;
}

fn introKeyNoop(g: *def.GameState, st: *nav.NavState, c: u8) bool {
    const out = nav.navStep(g, st, key(c));
    if (out != def.NAV_SUBDUE_INTRO) return false;
    if (g.screen != def.NAV_SUBDUE_INTRO) return false;
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    if (g.fight.def_index != 0) return false;
    return true;
}

fn tSubdueIntroBeforeSettle() bool {
    var g = pendingState(def.NAV_SUBDUE_INTRO);
    var st = nav.initState();

    if (!introKeyNoop(&g, &st, '1')) return false;
    if (!introKeyNoop(&g, &st, '2')) return false;
    if (!introKeyNoop(&g, &st, 'r')) return false;
    if (!introKeyNoop(&g, &st, 'R')) return false;
    if (!introKeyNoop(&g, &st, 's')) return false;
    if (!introKeyNoop(&g, &st, 'S')) return false;
    if (!introKeyNoop(&g, &st, 'x')) return false;

    if (nav.navStep(&g, &st, key('c')) != def.NAV_SETTLE) return false;
    if (g.screen != def.NAV_SETTLE) return false;
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    if (g.fight.def_index != 0) return false;

    var upper = pendingState(def.NAV_SUBDUE_INTRO);
    var ust = nav.initState();
    if (nav.navStep(&upper, &ust, key('C')) != def.NAV_SETTLE) return false;
    return true;
}

fn tSettleIgnoresRandS() bool {
    var g = pendingState(def.NAV_SETTLE);
    var st = nav.initState();
    const money = g.world.money;
    const bonus = g.world.release_bonus[1];
    const phases = g.world.field_phases;

    const keys = [6]u8{ 'r', 'R', 's', 'S', 'e', 'x' };
    var i: usize = 0;
    while (i < keys.len) : (i += 1) {
        if (nav.navStep(&g, &st, key(keys[i])) != def.NAV_SETTLE) return false;
        if (g.screen != def.NAV_SETTLE) return false;
        if (!(g.fight.outcome == def.OUT_SUBDUE and g.fight.def_index == 0)) return false;
        if (g.world.money != money) return false;
        if (g.world.release_bonus[1] != bonus) return false;
        if (g.world.field_phases != phases) return false;
    }
    return true;
}

fn tSettle1Releases2Sells() bool {
    const idx: i32 = 0;
    const zone: i32 = 1;
    const ri: usize = @intCast(usize, zone) * def.MAX_CREATURES
        + @intCast(usize, idx);

    var r = pendingState(def.NAV_SETTLE);
    var rst = nav.initState();
    const r_money = r.world.money;
    if (nav.navStep(&r, &rst, key('1')) != def.NAV_NODE) return false;
    if (r.fight.outcome == def.OUT_SUBDUE and r.fight.def_index != def.NO_FIGHT) return false;
    if (r.world.release_bonus[zone] != world.RELEASE_BONUS_STEP) return false;
    if (r.world.money != r_money) return false;
    if (r.world.ready[ri] == 0) return false;

    var s = pendingState(def.NAV_SETTLE);
    var sst = nav.initState();
    const sale = creatures.defAt(idx).sale;
    if (nav.navStep(&s, &sst, key('2')) != def.NAV_NODE) return false;
    if (s.fight.outcome == def.OUT_SUBDUE and s.fight.def_index != def.NO_FIGHT) return false;
    if (s.world.money != sale) return false;
    if (s.world.release_bonus[zone] != 0) return false;
    return true;
}

fn tSubdueIntroNoRngNoPhase() bool {
    var g = pendingState(def.NAV_SUBDUE_INTRO);
    var st = nav.initState();
    g.world.field_phases = 7;
    g.world.cycle = 3;
    g.world.phase = 1;
    g.world.rng_state = 0x9abcdef0;
    g.fight.rng_state = 0x12345678;
    g.fight.hp = 42;
    g.fight.res = 9;
    g.fight.hull = 80;
    g.exp.hold[1] = 3;
    const before = snap(&g);

    if (!introKeyNoop(&g, &st, '1')) return false;
    if (!introKeyNoop(&g, &st, '2')) return false;
    if (!introKeyNoop(&g, &st, 'r')) return false;
    if (!introKeyNoop(&g, &st, 's')) return false;
    if (!introKeyNoop(&g, &st, 'j')) return false;
    if (!snapSame(&g, before)) return false;

    if (nav.navStep(&g, &st, key('c')) != def.NAV_SETTLE) return false;
    return snapSame(&g, before);
}

fn lineIs(got: []const u8, want: []const u8) bool {
    if (got.len != want.len) return false;
    return std_mem.eqlU8(got.ptr, want.ptr, got.len);
}

fn fieldLine(st: *const nav.NavState) []const u8 {
    return st.field_msg[0..st.field_msg_len];
}

fn newDock() def.GameState {
    var g: def.GameState = undefined;
    game.newGame(&g);
    return g;
}
fn eventCopy(ev: i32, ev_def: i32, ev_value: i32, want: []const u8) bool {
    var g = newDock();
    var st = nav.initState();
    g.last_event = ev;
    g.last_event_def = ev_def;
    g.last_event_value = ev_value;
    _ = nav.navStep(&g, &st, key('x'));
    if (g.last_event != def.EV_NONE) return false;
    if (g.last_event_def != 0 or g.last_event_value != 0) return false;
    return lineIs(fieldLine(&st), want);
}
fn startFightAt(g: *def.GameState, idx: i32) void {
    game.startFight(g, idx);
    g.exp.active = 1;
    g.exp.zone = 0;
    g.world.hull = g.fight.hull;
}

const EventCopyCase = struct {
    name: []const u8,
    ev: i32,
    ev_def: i32,
    ev_value: i32,
    want: []const u8,
};

const EVENT_COPY_CASES = [_]EventCopyCase{
    .{ .name = "event_overkill_status", .ev = def.EV_OVERKILL, .ev_def = 0, .ev_value = def.OUT_OVERKILL, .want = "Overkilled Mystic Eel - the rarest line is ruined." },
    .{ .name = "event_creature_fled_status", .ev = def.EV_CREATURE_FLED, .ev_def = 0, .ev_value = 0, .want = "The creature fled - no loot; it renews." },
    .{ .name = "event_player_fled_status", .ev = def.EV_PLAYER_FLED, .ev_def = 0, .ev_value = 0, .want = "You fled - no loot; returned to dock." },
    .{ .name = "event_ascent_status", .ev = def.EV_ASCENT, .ev_def = 0, .ev_value = 0, .want = "Emergency ascent - Hull 0; returned to dock." },
    .{ .name = "event_released_status", .ev = def.EV_RELEASED, .ev_def = 0, .ev_value = 0, .want = "Released Mystic Eel - parts kept; +15 Resolve next time." },
    .{ .name = "event_sold_status", .ev = def.EV_SOLD, .ev_def = 0, .ev_value = 20, .want = "Sold Mystic Eel for 20 coins - parts kept." },
};

fn nodeCommand(zone: u8, action: u8, hull: i32, fight_index: i32,
    want: []const u8) bool {
    var g = newDock();
    var st = nav.initState();
    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (nav.navStep(&g, &st, key(zone)) != def.NAV_NODE) return false;
    if (hull >= 0) g.world.hull = hull;
    if (fight_index >= 0) g.exp.fight_index = fight_index;
    if (action != 0) _ = nav.navStep(&g, &st, key(action));
    if (g.last_event != def.EV_NONE) return false;
    return lineIs(fieldLine(&st), want);
}
fn tEventDepart() bool {
    return nodeCommand('2', 0, -1, -1,
        "Departed to The Reef - travel 2 out, 2 back (+1 depart action).");
}
fn tEventRestNode() bool {
    return nodeCommand('4', 'r', 90, -1, "Rested at the node: +10 Hull.");
}
fn tEventRough() bool {
    return eventCopy(def.EV_ROUGH, 0, def.COND_DROWSY, "Rough sleep (Drowsy): Strike -20%.")
        and eventCopy(def.EV_ROUGH, 0, def.COND_SHAKY, "Rough sleep (Shaky): overkill margin halved.")
        and eventCopy(def.EV_ROUGH, 0, def.COND_EXPOSED, "Rough sleep (Exposed): incoming damage +25%.");
}
fn tEventRestDock() bool {
    var g = newDock();
    var st = nav.initState();
    g.world.hull = 90;
    if (nav.navStep(&g, &st, key('t')) != def.NAV_DOCK) return false;
    if (g.last_event != def.EV_NONE) return false;
    return lineIs(fieldLine(&st), "Rested at dock: +10 Hull.");
}
fn tEventSurface() bool {
    return nodeCommand('2', 's', -1, -1, "Returned to dock - travel 2 phases.");
}
fn tEventSubdueNoStatus() bool {
    var g = newDock();
    var st = nav.initState();
    g.last_event = def.EV_SUBDUE;
    g.last_event_def = 0;
    _ = nav.navStep(&g, &st, key('x'));
    if (g.last_event != def.EV_NONE) return false;
    return st.field_msg_len == 0;
}
fn tEventKill() bool {
    return eventCopy(def.EV_KILL, 18, def.OUT_KILL, "Killed The Derelict.");
}
fn tEventHuntMax() bool {
    return nodeCommand('2', 'h', -1, 999, "No fights left - surface or rest.");
}
fn tEventHuntEmpty() bool {
    return nodeCommand('4', 'h', -1, -1, "Nothing answers the hook here.");
}
fn tEventBossLocked() bool {
    var g = newDock();
    var st = nav.initState();
    const gw = &g.world;
    gw.seen_mask[0] = 7;
    g.world.field_phases = 4;
    g.world.rng_state = 0xabc;
    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (nav.navStep(&g, &st, key('9')) != def.NAV_MAP) return false;
    if (g.screen != def.NAV_MAP) return false;
    if (g.exp.active != 0) return false;
    if (g.world.field_phases != 4) return false;
    if (g.world.rng_state != 0xabc) return false;
    if (g.last_event != def.EV_NONE) return false;
    return lineIs(fieldLine(&st), "The Derelict is silent - 3/6 species seen.");
}
fn tNoEventNoStatus() bool {
    var g = newDock();
    var st = nav.initState();
    if (nav.navStep(&g, &st, key('x')) != def.NAV_DOCK) return false;
    if (g.last_event != def.EV_NONE) return false;
    return st.field_msg_len == 0;
}

fn tStatusClearsNextKey() bool {
    var g = newDock();
    var st = nav.initState();
    if (nav.navStep(&g, &st, key('d')) != def.NAV_MAP) return false;
    if (nav.navStep(&g, &st, key('2')) != def.NAV_NODE) return false;
    if (st.field_msg_len == 0) return false;
    if (nav.navStep(&g, &st, key('x')) != def.NAV_NODE) return false;
    if (g.last_event != def.EV_NONE) return false;
    if (st.field_msg_len != 0) return false;
    return msgZeroed(st.field_msg[0..]);
}
fn tEventDoesNotChangePhaseOrRng() bool {
    var g = newDock();
    var st = nav.initState();
    g.exp.active = 1;
    g.exp.zone = 1;
    g.world.field_phases = 7;
    g.world.cycle = 3;
    g.world.phase = 1;
    g.world.rng_state = 0x9abcdef0;
    g.fight.rng_state = 0x12345678;
    g.world.hull = 55;
    g.world.money = 12;
    const before = snap(&g);

    g.screen = def.NAV_NODE;
    g.last_event = def.EV_REST_DOCK;
    g.last_event_def = 0;
    g.last_event_value = 40;
    if (nav.navStep(&g, &st, key('x')) != def.NAV_NODE) return false;

    if (g.last_event != def.EV_NONE) return false;
    return snapSame(&g, before)
        and lineIs(fieldLine(&st), "Rested at dock: +40 Hull.");
}

fn tKillOverkillFleeAscentSurviveScreenChange() bool {
    // Kill: 300 max HP gives a 30 margin, so 15 HP cannot overshoot it.
    var k = newDock();
    var kst = nav.initState();
    startFightAt(&k, 18);
    const kidx = k.fight.def_index;
    var kcdef = creatures.defAt(kidx);
    const kname = kcdef.name[0..@intCast(usize, kcdef.name_len)];
    k.fight.hp = 15;
    if (nav.navStep(&k, &kst, key('s')) != def.NAV_NODE) return false;
    if (expedition.isInFight(&k)) return false;
    if (k.last_event != def.EV_NONE) return false;
    var kbuf: [96]u8 = undefined;
    var kp: usize = 0;
    text_scan.appendText(kbuf[0..], &kp, "Killed ");
    text_scan.appendText(kbuf[0..], &kp, kname);
    text_scan.appendText(kbuf[0..], &kp, ".");
    if (!lineIs(fieldLine(&kst), kbuf[0..kp])) return false;

    // Overkill: 1 HP on the 70 HP eel is above its 7 margin.
    var o = newDock();
    var ost = nav.initState();
    startFightAt(&o, 0);
    const oidx = o.fight.def_index;
    var ocdef = creatures.defAt(oidx);
    const oname = ocdef.name[0..@intCast(usize, ocdef.name_len)];
    o.fight.hp = 1;
    if (nav.navStep(&o, &ost, key('s')) != def.NAV_NODE) return false;
    if (expedition.isInFight(&o)) return false;
    if (o.last_event != def.EV_NONE) return false;
    var obuf: [96]u8 = undefined;
    var op: usize = 0;
    text_scan.appendText(obuf[0..], &op, "Overkilled ");
    text_scan.appendText(obuf[0..], &op, oname);
    text_scan.appendText(obuf[0..], &op, " - the rarest line is ruined.");
    if (!lineIs(fieldLine(&ost), obuf[0..op])) return false;

    // Creature flee: stay at the node, no loot.
    var c = newDock();
    var cst = nav.initState();
    startFightAt(&c, 0);
    c.fight.pending_flee = 1;
    if (nav.navStep(&c, &cst, key('s')) != def.NAV_NODE) return false;
    if (expedition.isInFight(&c)) return false;
    if (c.last_event != def.EV_NONE) return false;
    if (!lineIs(fieldLine(&cst), "The creature fled - no loot; it renews.")) return false;

    // Player flee: return to dock.
    var f = newDock();
    var fst = nav.initState();
    startFightAt(&f, 0);
    if (nav.navStep(&f, &fst, key('f')) != def.NAV_DOCK) return false;
    if (f.exp.active != 0) return false;
    if (f.last_event != def.EV_NONE) return false;
    if (!lineIs(fieldLine(&fst), "You fled - no loot; returned to dock.")) return false;

    // Hull-0 ascent: return to dock, Hull 0.
    var a = newDock();
    var ast = nav.initState();
    startFightAt(&a, 0);
    a.fight.hull = 0;
    if (nav.navStep(&a, &ast, key('s')) != def.NAV_DOCK) return false;
    if (expedition.isInFight(&a)) return false;
    if (a.exp.active != 0) return false;
    if (a.world.hull != 0) return false;
    if (a.last_event != def.EV_NONE) return false;
    return lineIs(fieldLine(&ast), "Emergency ascent - Hull 0; returned to dock.");
}

fn tReleaseSellResultLine() bool {
    var r = pendingState(def.NAV_SETTLE);
    var rst = nav.initState();
    if (nav.navStep(&r, &rst, key('1')) != def.NAV_NODE) return false;
    if (r.last_event != def.EV_NONE) return false;
    if (!lineIs(fieldLine(&rst),
        "Released Mystic Eel - parts kept; +15 Resolve next time.")) return false;

    var s = pendingState(def.NAV_SETTLE);
    var sst = nav.initState();
    if (nav.navStep(&s, &sst, key('2')) != def.NAV_NODE) return false;
    if (s.last_event != def.EV_NONE) return false;
    return lineIs(fieldLine(&sst), "Sold Mystic Eel for 20 coins - parts kept.");
}
fn tWaryLog() bool {
    var g = newDock();
    _ = expedition.depart(&g, 1);
    const gw = &g.world;
    gw.wary_mask[0] = 0xFFFFFFFF;
    gw.wary_mask[1] = 0xFFFFFFFF;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    return expedition.isInFight(&g) and logHas(&g, def.MSG_WARY)
        and logText(&g, def.MSG_WARY, "This one remembers: +15 Resolve.");
}

fn tGrudgeLog() bool {
    var r = newDock();
    world.markTaken(&r.world, 0, 0, def.OUT_OVERKILL);
    game.startFight(&r, 10);
    if (!logHas(&r, def.MSG_GRUDGE)
        or !logText(&r, def.MSG_GRUDGE,
            "It remembers the last run: +30 Resolve.")) return false;
    var a = newDock();
    world.markTaken(&a.world, 0, 2, def.OUT_OVERKILL);
    game.startFight(&a, 11);
    return logHas(&a, def.MSG_GRUDGE) and logText(&a, def.MSG_GRUDGE,
        "It remembers the last run: armor drops to 30%.");
}

pub fn main() void {
    report("init_state_zeroes_every_field", tInitStateZeroesEveryField());
    report("field_msg_cleared_on_next_key", tFieldMsgClearedOnNextKey());
    report("nav_result_line_prefers_field_msg", tNavResultLinePrefersFieldMsg());
    report("field_msg_does_not_change_phase_or_rng", tFieldMsgDoesNotChangePhaseOrRng());
    report("subdue_intro_before_settle", tSubdueIntroBeforeSettle());
    report("settle_ignores_r_and_s", tSettleIgnoresRandS());
    report("settle_1_releases_2_sells", tSettle1Releases2Sells());
    report("subdue_intro_no_rng_no_phase", tSubdueIntroNoRngNoPhase());
    report("event_depart_status", tEventDepart());
    report("event_rest_node_status", tEventRestNode());
    report("event_rough_status", tEventRough());
    report("event_rest_dock_status", tEventRestDock());
    report("event_surface_status", tEventSurface());
    report("event_subdue_no_status", tEventSubdueNoStatus());
    report("event_kill_status", tEventKill());
    var ci: usize = 0;
    while (ci < EVENT_COPY_CASES.len) : (ci += 1) {
        const c = EVENT_COPY_CASES[ci];
        report(c.name, eventCopy(c.ev, c.ev_def, c.ev_value, c.want));
    }
    report("event_hunt_max_status", tEventHuntMax());
    report("event_hunt_empty_status", tEventHuntEmpty());
    report("event_boss_locked_status", tEventBossLocked());
    report("no_event_no_status", tNoEventNoStatus());
    report("status_clears_next_key", tStatusClearsNextKey());
    report("event_does_not_change_phase_or_rng", tEventDoesNotChangePhaseOrRng());
    report("kill_overkill_flee_ascent_survive_screen_change",
        tKillOverkillFleeAscentSurviveScreenChange());
    report("release_sell_result_line", tReleaseSellResultLine());
    report("wary_log_at_fight_start", tWaryLog());
    report("grudge_log_at_fight_start", tGrudgeLog());

    if (fails != 0) os.exit(1);
    io.write("ux_test PASS\n");
}
