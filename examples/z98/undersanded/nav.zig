// nav.zig — UNDERSANDED M5 playable console navigation (spec §12, §16, §26).
//
// Pure navigation: navStep maps one key to the next nav screen id and mutates
// game state only through the dock/expedition entry points. All I/O lives in
// navRun (one stdin key per frame); there is no gfx and no RNG of our own.
//
// Nav screen ids live in def and stay disjoint from def.SCREEN_* (0..2).
// GameState.screen carries the nav id while navigating; fight.zig overwrites
// it with def.SCREEN_FIGHT/def.SCREEN_SUBDUE when a fight starts.
//
// UI-only state (the rare-batch two-press confirm and the last dock result)
// lives in NavState, never GameState (R16).

const io = @import("std_io.zig");
const def = @import("def.zig");
const input = @import("input.zig");
const expedition = @import("expedition.zig");
const creatures = @import("creatures_t1.zig");
const dock = @import("dock.zig");
const data = @import("data.zig");
const render = @import("render_term.zig");
const paths = @import("paths.zig");
const save_ux = @import("save_ux.zig");
const game = @import("game.zig");
const persist = @import("persist.zig");
const journal = @import("journal.zig");
const fight = @import("fight.zig");
const text_scan = @import("text_scan.zig");
const render_text = @import("render_text.zig");
const economy = @import("economy.zig");

pub const HELP_PAGE_NONE: i32 = 0;
pub const TIP_NONE: i32 = 0;

// Boot action ids: pure menu/confirm/error decisions shared by tests and the
// nav.boot I/O loop.
pub const BOOT_ACT_NONE: i32 = 0;
pub const BOOT_ACT_CONTINUE: i32 = 1;
pub const BOOT_ACT_NEW: i32 = 2;
pub const BOOT_ACT_OPTIONS: i32 = 3;
pub const BOOT_ACT_QUIT: i32 = 4;
pub const BOOT_ACT_FRESH: i32 = 5;
pub const BOOT_ACT_BACKUP: i32 = 6;
pub const BOOT_ACT_YES: i32 = 7;
pub const BOOT_ACT_NO: i32 = 8;

pub const NavState = struct {
    armed: i32,
    last: i32,
    save_err_kind: i32,
    help_page: i32,
    tip: i32,
    journal_sel: i32,
    // Boot-only: 0 none, 1 awaiting the New Game Y/N answer. navStep never
    // reads it, so console nav behaviour is unchanged.
    boot_pending: i32,
    // M10.1 one-action field status line (UI-only, spec §7.1).
    field_msg: [96]u8,
    field_msg_len: usize,
};

// R8 explicit initialisation for every NavState constructor (R8).
pub fn initState() NavState {
    var st: NavState = undefined;
    st.armed = 0;
    st.last = def.NAV_RESULT_NONE;
    st.save_err_kind = 0;
    st.help_page = HELP_PAGE_NONE;
    st.tip = TIP_NONE;
    st.journal_sel = 0;
    st.boot_pending = 0;
    st.field_msg_len = 0;
    var i: usize = 0;
    while (i < st.field_msg.len) : (i += 1) {
        st.field_msg[i] = 0;
    }
    return st;
}

pub fn navClearFieldMsg(st: *NavState) void {
    st.field_msg_len = 0;
    var i: usize = 0;
    while (i < st.field_msg.len) : (i += 1) {
        st.field_msg[i] = 0;
    }
}

pub fn navSetFieldMsg(st: *NavState, text: []const u8) void {
    var i: usize = 0;
    while (i < text.len and i < st.field_msg.len) : (i += 1) {
        st.field_msg[i] = text[i];
    }
    st.field_msg_len = i;
}

pub fn navSetFieldMsgInt(st: *NavState, prefix: []const u8, value: i32,
    suffix: []const u8) void {
    var at: usize = 0;
    text_scan.appendText(st.field_msg[0..], &at, prefix);
    text_scan.appendInt(st.field_msg[0..], &at, @intCast(i64, value));
    text_scan.appendText(st.field_msg[0..], &at, suffix);
    st.field_msg_len = at;
}

fn eventCondName(cond: i32) []const u8 {
    if (cond == def.COND_DROWSY or cond == def.COND_SHAKY or cond == def.COND_EXPOSED) {
        return render_text.conditionName(cond);
    }
    return "rough";
}

fn eventCondEffect(cond: i32) []const u8 {
    if (cond == def.COND_DROWSY or cond == def.COND_SHAKY or cond == def.COND_EXPOSED) {
        return render_text.conditionEffect(cond);
    }
    return "the sleep takes its toll";
}

// Consume one transient §7.1 field event into the one-action status line.
// Called after the action so early returns cannot skip it. EV_SUBDUE has its
// own intro screen and deliberately produces no status line.
pub fn navConsumeEvent(g: *def.GameState, st: *NavState) void {
    const ev = g.last_event;
    const ev_def = g.last_event_def;
    const ev_value = g.last_event_value;
    g.last_event = def.EV_NONE;
    g.last_event_def = 0;
    g.last_event_value = 0;

    var buf: [256]u8 = undefined;
    var p: usize = 0;
    switch (ev) {
        def.EV_DEPART => {
            text_scan.appendText(buf[0..], &p, "Departed to ");
            text_scan.appendText(buf[0..], &p, render.zoneName(ev_def));
            text_scan.appendText(buf[0..], &p, " - travel ");
            text_scan.appendInt(buf[0..], &p, @intCast(i64, ev_value));
            text_scan.appendText(buf[0..], &p, " out, ");
            text_scan.appendInt(buf[0..], &p, @intCast(i64, ev_value));
            text_scan.appendText(buf[0..], &p, " back (+1 depart action).");
            navSetFieldMsg(st, buf[0..p]);
        },
        def.EV_REST_NODE => {
            navSetFieldMsgInt(st, "Rested at the node: +", ev_value, " Hull.");
        },
        def.EV_ROUGH => {
            text_scan.appendText(buf[0..], &p, "Rough sleep (");
            text_scan.appendText(buf[0..], &p, eventCondName(ev_value));
            text_scan.appendText(buf[0..], &p, "): ");
            text_scan.appendText(buf[0..], &p, eventCondEffect(ev_value));
            text_scan.appendText(buf[0..], &p, ".");
            navSetFieldMsg(st, buf[0..p]);
        },
        def.EV_REST_DOCK => {
            navSetFieldMsgInt(st, "Rested at dock: +", ev_value, " Hull.");
        },
        def.EV_SURFACE => {
            navSetFieldMsgInt(st, "Returned to dock - travel ", ev_value, " phases.");
        },
        def.EV_SUBDUE => {},
        def.EV_KILL => {
            if (ev_def < 0 or ev_def >= creatures.defCount()) return;
            var cdef = creatures.defAt(ev_def);
            const name = render.creatureName(&cdef);
            text_scan.appendText(buf[0..], &p, "Killed ");
            text_scan.appendText(buf[0..], &p, name);
            text_scan.appendText(buf[0..], &p, ".");
            navSetFieldMsg(st, buf[0..p]);
        },
        def.EV_OVERKILL => {
            if (ev_def < 0 or ev_def >= creatures.defCount()) return;
            var cdef = creatures.defAt(ev_def);
            const name = render.creatureName(&cdef);
            text_scan.appendText(buf[0..], &p, "Overkilled ");
            text_scan.appendText(buf[0..], &p, name);
            text_scan.appendText(buf[0..], &p, " - the rarest line is ruined.");
            navSetFieldMsg(st, buf[0..p]);
        },
        def.EV_CREATURE_FLED => {
            navSetFieldMsg(st, "The creature fled - no loot; it renews.");
        },
        def.EV_PLAYER_FLED => {
            navSetFieldMsg(st, "You fled - no loot; returned to dock.");
        },
        def.EV_ASCENT => {
            navSetFieldMsg(st, "Emergency ascent - Hull 0; returned to dock.");
        },
        def.EV_HUNT_MAX => {
            navSetFieldMsg(st, "No fights left - surface or rest.");
        },
        def.EV_HUNT_EMPTY => {
            navSetFieldMsg(st, "Nothing answers the hook here.");
        },
        def.EV_BOSS_LOCKED => {
            navSetFieldMsgInt(st, "The Derelict is silent - ", ev_value,
                "/6 species seen.");
        },
        def.EV_RELEASED => {
            if (ev_def < 0 or ev_def >= creatures.defCount()) return;
            var cdef = creatures.defAt(ev_def);
            const name = render.creatureName(&cdef);
            text_scan.appendText(buf[0..], &p, "Released ");
            text_scan.appendText(buf[0..], &p, name);
            text_scan.appendText(buf[0..], &p, " - parts kept; +15 Resolve next time.");
            navSetFieldMsg(st, buf[0..p]);
        },
        def.EV_SOLD => {
            if (ev_def < 0 or ev_def >= creatures.defCount()) return;
            var cdef = creatures.defAt(ev_def);
            const name = render.creatureName(&cdef);
            text_scan.appendText(buf[0..], &p, "Sold ");
            text_scan.appendText(buf[0..], &p, name);
            text_scan.appendText(buf[0..], &p, " for ");
            text_scan.appendInt(buf[0..], &p, @intCast(i64, ev_value));
            text_scan.appendText(buf[0..], &p, " coins - parts kept.");
            navSetFieldMsg(st, buf[0..p]);
        },
        else => {},
    }
}

pub const BootOut = struct {
    screen: i32,
    done: bool,
    quit: bool,
    msg_len: usize,
};

pub const NavIntercept = struct {
    handled: bool,
    quit: bool,
    msg: []const u8,
};

fn lower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn isChar(k: input.Key, c: u8) bool {
    return lower(k.ch) == c;
}

// Boot routing is pure: the caller decides whether the active slot save exists.
pub fn bootStartScreen(save_exists: bool) i32 {
    if (save_exists) return def.NAV_MENU;
    return def.NAV_LORE;
}

pub fn menuAction(k: input.Key) i32 {
    if (isChar(k, 'c')) return BOOT_ACT_CONTINUE;
    if (isChar(k, 'n')) return BOOT_ACT_NEW;
    if (isChar(k, 'o')) return BOOT_ACT_OPTIONS;
    if (isChar(k, 'q')) return BOOT_ACT_QUIT;
    return BOOT_ACT_NONE;
}

pub fn confirmAction(k: input.Key) i32 {
    if (isChar(k, 'y')) return BOOT_ACT_YES;
    if (isChar(k, 'n')) return BOOT_ACT_NO;
    return BOOT_ACT_NONE;
}

pub fn errorAction(k: input.Key) i32 {
    if (isChar(k, 'f')) return BOOT_ACT_FRESH;
    if (isChar(k, 'b')) return BOOT_ACT_BACKUP;
    if (isChar(k, 'q')) return BOOT_ACT_QUIT;
    return BOOT_ACT_NONE;
}

pub fn firstRunAdvance(k: input.Key) bool {
    return k.ch == 10 or k.ch == 13 or k.ch == ' ' or k.code == 10 or k.code == 13;
}

fn isEsc(k: input.Key) bool {
    if (k.ch == input.KEY_ESC) return true;
    if (k.code == input.VK_ESC) return true;
    if (k.code == input.KEY_ESC) return true;
    return false;
}

fn isPending(g: *const def.GameState) bool {
    return g.fight.outcome == def.OUT_SUBDUE and g.fight.def_index != def.NO_FIGHT;
}

// Pending choice -> preserve the intro until C, otherwise settle; an active
// expedition -> node, else dock.
fn deriveScreen(g: *const def.GameState) i32 {
    if (isPending(g)) {
        if (g.screen == def.NAV_SUBDUE_INTRO) return def.NAV_SUBDUE_INTRO;
        return def.NAV_SETTLE;
    }
    if (g.exp.active != 0) return def.NAV_NODE;
    return def.NAV_DOCK;
}

fn setScreen(g: *def.GameState, screen: i32) i32 {
    g.screen = screen;
    return screen;
}

// A field action may start a fight; keep def.SCREEN_* in that case so
// the next key still maps through input.mapKey. A subdue intro is a field
// screen too: postFight owns it and this must not overwrite it.
fn screenAfterField(g: *def.GameState) i32 {
    if (expedition.isInFight(g)) return g.screen;
    if (isPending(g) and g.screen == def.NAV_SUBDUE_INTRO) return g.screen;
    return deriveScreen(g);
}

fn dockStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    st.armed = 0;
    if (isChar(key, 'q')) return def.NAV_QUIT;
    if (isChar(key, 'd')) return setScreen(g, def.NAV_MAP);
    if (isChar(key, 't')) expedition.restAtDock(g);
    if (isChar(key, 'r')) return setScreen(g, def.NAV_REFINE);
    if (isChar(key, 'u')) return setScreen(g, def.NAV_UPGRADE);
    if (isChar(key, 'c')) return setScreen(g, def.NAV_CRAFT);
    if (isChar(key, 'b')) return setScreen(g, def.NAV_BUY);
    if (isChar(key, 'e')) return setScreen(g, def.NAV_TOOLS);
    return setScreen(g, def.NAV_DOCK);
}

// Refine sub-menu: common parts execute on one press; Glow Polyp (6) and Glass
// Pane (7) arm a rare-batch preview and execute on the same key again. Any
// other key cancels the arm; Esc backs out to the dock (R11/P22.9).
fn refineStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) {
        st.armed = 0;
        return setScreen(g, def.NAV_DOCK);
    }

    if (key.ch >= '1' and key.ch <= '7') {
        const material: i32 = @intCast(i32, key.ch - '0');
        if (st.armed != 0 and st.armed != material) {
            st.armed = 0;
            return setScreen(g, def.NAV_REFINE);
        }
        if (economy.isDeepMaterial(material) and st.armed != material
            and dock.refineParts(g, material) > 0) {
            st.armed = material;
            st.last = def.NAV_RESULT_PREVIEW;
            return setScreen(g, def.NAV_REFINE);
        }
        st.armed = 0;
        st.last = dock.dockRefine(g, material);
        return setScreen(g, def.NAV_REFINE);
    }

    // Any other key cancels a pending rare-batch confirm.
    st.armed = 0;
    return setScreen(g, def.NAV_REFINE);
}

fn upgradeStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, def.NAV_DOCK);
    if (key.ch >= '1' and key.ch <= '5') {
        const axis: i32 = @intCast(i32, key.ch - '1');
        st.last = dock.dockUpgrade(g, axis);
    }
    return setScreen(g, def.NAV_UPGRADE);
}

fn craftStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, def.NAV_DOCK);
    if (key.ch >= '1' and key.ch <= '7') {
        const tool: i32 = @intCast(i32, key.ch - '0');
        st.last = dock.dockCraft(g, tool);
    }
    return setScreen(g, def.NAV_CRAFT);
}

fn buyStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, def.NAV_DOCK);
    const c = lower(key.ch);
    if (c >= '1' and c <= '9') {
        const cosmetic: i32 = @intCast(i32, c - '1');
        st.last = dock.dockBuy(g, cosmetic);
    } else if (c >= 'a' and c <= 'c') {
        const cosmetic: i32 = @intCast(i32, 9 + (c - 'a'));
        st.last = dock.dockBuy(g, cosmetic);
    }
    return setScreen(g, def.NAV_BUY);
}

fn toolsStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, def.NAV_DOCK);
    if (isChar(key, '0')) {
        st.last = dock.dockSelectTool(g, 0);
    } else if (key.ch >= '1' and key.ch <= '7') {
        const tool: i32 = @intCast(i32, key.ch - '0');
        st.last = dock.dockSelectTool(g, tool);
    }
    return setScreen(g, def.NAV_TOOLS);
}

fn mapStep(g: *def.GameState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, def.NAV_DOCK);

    if (key.ch >= '1' and key.ch <= '8') {
        const zone: i32 = @intCast(i32, key.ch - '1');
        _ = expedition.depart(g, zone);
        return setScreen(g, def.NAV_NODE);
    }

    if (key.ch == '9') {
        if (render.bossGateOpen(g)) {
            _ = expedition.depart(g, 8);
            return setScreen(g, def.NAV_NODE);
        }
        g.last_event = def.EV_BOSS_LOCKED;
        g.last_event_def = 0;
        g.last_event_value = render.seenNonBossCount(g);
    }

    // Locked boss or any other key stays on the map.
    return setScreen(g, def.NAV_MAP);
}

fn nodeStep(g: *def.GameState, key: input.Key) i32 {
    if (isChar(key, 'h')) {
        expedition.expeditionStep(g, expedition.EXP_HUNT);
        return setScreen(g, screenAfterField(g));
    }
    if (isChar(key, 'r')) {
        expedition.expeditionStep(g, expedition.EXP_REST);
        return setScreen(g, screenAfterField(g));
    }
    if (isChar(key, 's')) {
        expedition.expeditionStep(g, expedition.EXP_SURFACE);
        return setScreen(g, screenAfterField(g));
    }
    return setScreen(g, def.NAV_NODE);
}

fn journalStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (st.journal_sel > 0) {
        if (isEsc(key)) st.journal_sel = 0;
        return setScreen(g, def.NAV_JOURNAL);
    }
    if (isEsc(key)) {
        st.journal_sel = 0;
        return setScreen(g, deriveScreen(g));
    }

    var idx: i32 = -1;
    if (key.ch >= '1' and key.ch <= '9') {
        idx = @intCast(i32, key.ch - '1');
    } else {
        const c = lower(key.ch);
        if (c >= 'a' and c <= 'j') idx = 9 + @intCast(i32, c - 'a');
    }
    if (idx >= 0 and idx < creatures.defCount()) {
        if (journal.journalOpen(&g.world, idx)) st.journal_sel = idx + 1;
    }
    return setScreen(g, def.NAV_JOURNAL);
}

// Inner step: every action path returns through here so the wrapper below can
// always consume the transient field event exactly once.
fn navStepInner(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    navClearFieldMsg(st);
    st.last = def.NAV_RESULT_NONE;
    st.tip = TIP_NONE;

    // (0) Help overlay: `?` works on every screen (including mid-fight) and
    // never forwards an action or draws RNG. Any key dismisses the page.
    if (st.help_page != HELP_PAGE_NONE) {
        st.help_page = HELP_PAGE_NONE;
        return setScreen(g, g.screen);
    }
    if (key.ch == '?') {
        st.help_page = journal.helpPageNumber(g.screen);
        return setScreen(g, g.screen);
    }

    // (1) A live fight consumes the key through the fight key map, then the
    // post-fight state decides which nav screen comes next.
    if (expedition.isInFight(g)) {
        if (input.mapKey(g.screen, key)) |act| {
            if (act.kind == def.ACT_RESTRAIN) {
                if (journal.tooltipShow(&g.world, journal.TOOLTIP_RESTRAIN) != null) {
                    st.tip = journal.TOOLTIP_RESTRAIN + 1;
                }
            }
            expedition.expeditionStep(g, act.kind);
        }
        if (expedition.isInFight(g) and st.tip == TIP_NONE) {
            if (g.fight.hp <= fight.dangerHp(&g.fight)) {
                if (journal.tooltipShow(&g.world, journal.TOOLTIP_RED_ZONE) != null) {
                    st.tip = journal.TOOLTIP_RED_ZONE + 1;
                }
            }
        }
        // Keep def.SCREEN_* while the fight runs; only an ended fight
        // hands the screen back to nav.
        return setScreen(g, screenAfterField(g));
    }

    // (2) A pending Subdue choice must be settled before anything else. The
    // intro screen accepts only C/c; settle accepts only 1/2. R/S and every
    // other key are no-ops so an irreversible choice is never one key away.
    if (isPending(g)) {
        if (g.screen == def.NAV_SUBDUE_INTRO) {
            if (isChar(key, 'c')) return setScreen(g, def.NAV_SETTLE);
            return setScreen(g, def.NAV_SUBDUE_INTRO);
        }
        if (g.screen != def.NAV_SETTLE) return setScreen(g, def.NAV_SETTLE);
        if (key.ch == '1') {
            expedition.resolveSubdueChoice(g, expedition.SUB_RELEASE);
        } else if (key.ch == '2') {
            expedition.resolveSubdueChoice(g, expedition.SUB_SELL);
        }
        return setScreen(g, deriveScreen(g));
    }

    // `J` opens the Journal everywhere but mid-fight (including settle/submenus).
    if (isChar(key, 'j') and g.screen != def.NAV_JOURNAL) {
        st.journal_sel = 0;
        return setScreen(g, def.NAV_JOURNAL);
    }

    // (3) Field and dock sub-menu screens. An uninitialised screen id is
    // treated as the dock.
    switch (g.screen) {
        def.NAV_MAP => return mapStep(g, key),
        def.NAV_NODE => return nodeStep(g, key),
        def.NAV_REFINE => return refineStep(g, st, key),
        def.NAV_UPGRADE => return upgradeStep(g, st, key),
        def.NAV_CRAFT => return craftStep(g, st, key),
        def.NAV_BUY => return buyStep(g, st, key),
        def.NAV_TOOLS => return toolsStep(g, st, key),
        def.NAV_LORE => return setScreen(g, def.NAV_LORE),
        def.NAV_MENU => return setScreen(g, def.NAV_MENU),
        def.NAV_SAVE_ERR => return setScreen(g, def.NAV_SAVE_ERR),
        def.NAV_JOURNAL => return journalStep(g, st, key),
        def.NAV_HELP => return setScreen(g, def.NAV_HELP),
        else => return dockStep(g, st, key),
    }
}

// Next screen id for one key. Mutates game state only via dock/expedition.
pub fn navStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    const next = navStepInner(g, st, key);
    navConsumeEvent(g, st);
    return next;
}

// ---- prepared views for the decoupled terminal renderers ------------------

fn initView(g: *const def.GameState, screen: i32, out: *render.View) void {
    out.screen = screen;
    out.g = g;
    out.journal_has_new = false;
    out.save_ok = true;
    out.save_block = "";
    out.journal_sel = 0;
    out.journal_text = "";
    out.journal_text_found = false;
    out.zone_flavour = "";
    out.zone_flavour_found = false;
    out.heavy_active = false;
    out.node_pool = 0;
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        out.zone_cost[i] = 0;
    }
    i = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        out.refine_parts[i] = 0;
        out.refine_per_part[i] = 0;
    }
    i = 0;
    while (i < 15) : (i += 1) {
        out.upgrade_cost[i] = def.CostSlot{ .kind = 0, .amt = 0 };
        out.upgrade_cost_is_material[i] = false;
    }
    i = 0;
    while (i < def.MAX_COSMETICS) : (i += 1) {
        out.cosmetic_status[i] = render.COSMETIC_LOCKED;
    }
    i = 0;
    while (i < def.MAX_CREATURES) : (i += 1) {
        out.journal_unlocked[i] = false;
        out.journal_viewed[i] = false;
    }
}

pub fn prepareDock(g: *const def.GameState, out: *render.View) void {
    initView(g, g.screen, out);
    out.journal_has_new = journal.journalHasNew(&g.world);
    if (save_ux.canSave(g)) |reason| {
        out.save_ok = false;
        out.save_block = reason;
    }
}

pub fn prepareRefine(g: *const def.GameState, out: *render.View) void {
    initView(g, g.screen, out);
    var m: i32 = 1;
    while (m <= 7) : (m += 1) {
        const mi: usize = @intCast(usize, m);
        out.refine_parts[mi] = dock.refineParts(g, m);
        out.refine_per_part[mi] = dock.refinePerPart(g, m);
    }
}

pub fn prepareUpgrade(g: *const def.GameState, out: *render.View) void {
    initView(g, g.screen, out);
    var axis: i32 = 0;
    while (axis < 5) : (axis += 1) {
        const tier = g.world.boat[@intCast(usize, axis)];
        if (tier >= 3) continue;
        var cost: [3]economy.MaterialAmt = [3]economy.MaterialAmt{
            .{ .kind = 0, .amt = 0 },
            .{ .kind = 0, .amt = 0 },
            .{ .kind = 0, .amt = 0 },
        };
        economy.upgradeCost(axis, tier + 1, &cost);
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const base = @intCast(usize, axis) * 3 + i;
            out.upgrade_cost[base] = def.CostSlot{ .kind = cost[i].kind, .amt = cost[i].amt };
            out.upgrade_cost_is_material[base] =
                cost[i].kind >= economy.MAT_CHITIN and cost[i].kind <= economy.MAT_GLASS;
        }
    }
}

pub fn prepareBuy(g: *const def.GameState, out: *render.View) void {
    initView(g, g.screen, out);
    var i: i32 = 0;
    while (i < @intCast(i32, def.MAX_COSMETICS)) : (i += 1) {
        const idx: usize = @intCast(usize, i);
        if (dock.cosmeticOwned(&g.world, i)) {
            out.cosmetic_status[idx] = render.COSMETIC_OWNED;
        } else if (!dock.cosmeticUnlocked(&g.world, i)) {
            out.cosmetic_status[idx] = render.COSMETIC_LOCKED;
        } else {
            out.cosmetic_status[idx] = render.COSMETIC_AVAILABLE;
        }
    }
}

pub fn prepareJournal(g: *const def.GameState, sel: i32, out: *render.View) void {
    initView(g, def.NAV_JOURNAL, out);
    out.journal_sel = sel;
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        const di: usize = @intCast(usize, d);
        out.journal_unlocked[di] = journal.journalUnlocked(&g.world, d);
        out.journal_viewed[di] = journal.journalViewed(&g.world, d);
    }
    if (sel > 0) {
        const si = sel - 1;
        var key_buf: [24]u8 = undefined;
        const key = journal.journalKey(si, key_buf[0..]);
        if (data.textFind(key)) |text| {
            out.journal_text = text;
            out.journal_text_found = true;
        }
    }
}

pub fn prepareMap(g: *const def.GameState, out: *render.View) void {
    initView(g, def.NAV_MAP, out);
    out.heavy_active = expedition.heavyActive(g);
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        out.zone_cost[i] = expedition.travelCostForZone(g, @intCast(i32, i));
    }
}

pub fn prepareNode(g: *const def.GameState, out: *render.View) void {
    initView(g, g.screen, out);
    out.node_pool = expedition.poolCount(g);
    var zkey: [24]u8 = undefined;
    const ztext = render_text.keyIntInto("zone.", g.exp.zone + 1, zkey[0..]);
    if (data.textFind(ztext)) |flavour| {
        out.zone_flavour = flavour;
        out.zone_flavour_found = true;
    }
}

pub fn drawScreen(g: *def.GameState, st: *const NavState, sc: *render.Screen) void {
    if (st.help_page != HELP_PAGE_NONE) {
        const page = journal.helpPage(g.screen) orelse "(manual text unavailable)";
        render.renderHelp(page, sc);
        return;
    }
    if (expedition.isInFight(g)) {
        var d = creatures.defAt(g.fight.def_index);
        render.renderFrame(g, &d, sc);
    } else switch (g.screen) {
        def.NAV_MAP => {
            var v: render.View = undefined;
            prepareMap(g, &v);
            render.renderMap(&v, sc);
        },
        def.NAV_NODE, def.NAV_SETTLE, def.NAV_SUBDUE_INTRO => {
            var v: render.View = undefined;
            prepareNode(g, &v);
            render.renderNode(&v, sc);
        },
        def.NAV_REFINE => {
            var v: render.View = undefined;
            prepareRefine(g, &v);
            render.renderRefine(&v, sc);
        },
        def.NAV_UPGRADE => {
            var v: render.View = undefined;
            prepareUpgrade(g, &v);
            render.renderUpgrade(&v, sc);
        },
        def.NAV_CRAFT => render.renderCraft(g, sc),
        def.NAV_BUY => {
            var v: render.View = undefined;
            prepareBuy(g, &v);
            render.renderBuy(&v, sc);
        },
        def.NAV_TOOLS => render.renderTools(g, sc),
        def.NAV_LORE => render.renderLore(save_ux.manualPageOne(), sc),
        def.NAV_MENU => render.renderMenu(sc),
        def.NAV_SAVE_ERR => render.renderSaveError(save_ux.saveErrTextKind(st.save_err_kind), sc),
        def.NAV_JOURNAL => {
            var v: render.View = undefined;
            prepareJournal(g, st.journal_sel, &v);
            render.renderJournal(&v, sc);
        },
        def.NAV_HELP => {
            const page = journal.helpPage(g.screen) orelse "(manual text unavailable)";
            render.renderHelp(page, sc);
        },
        else => {
            var v: render.View = undefined;
            prepareDock(g, &v);
            render.renderDock(&v, sc);
        },
    }
}

pub fn drawCurrent(g: *def.GameState, st: *const NavState, out: []u8) []const u8 {
    var sc: render.Screen = undefined;
    drawScreen(g, st, &sc);
    return render.dump(&sc, out);
}

pub fn navTipLine(st: *const NavState) []const u8 {
    if (st.tip != TIP_NONE) {
        if (journal.tooltip(st.tip - 1)) |tip| return tip;
    }
    return "";
}

pub fn navResultLine(g: *def.GameState, st: *const NavState, out: []u8) []const u8 {
    if (st.field_msg_len > 0) return st.field_msg[0..st.field_msg_len];
    if (st.last >= 0) return dock.resultText(st.last);
    if (st.last == def.NAV_RESULT_PREVIEW) {
        const parts = dock.refineParts(g, st.armed);
        const total = parts * dock.refinePerPart(g, st.armed);
        var at: usize = 0;
        text_scan.appendText(out, &at, "Rare batch: ");
        text_scan.appendInt(out, &at, @intCast(i64, parts));
        text_scan.appendText(out, &at, " parts -> ");
        text_scan.appendInt(out, &at, @intCast(i64, total));
        text_scan.appendText(out, &at, " materials (expertise +1). Press again to confirm; Esc cancels.");
        return out[0..at];
    }
    return "";
}

pub fn navQuitKey(g: *const def.GameState, st: *const NavState, key: input.Key) bool {
    if (st.help_page != HELP_PAGE_NONE) return false;
    if (g.screen != def.NAV_DOCK) return false;
    return isChar(key, 'q') and save_ux.quitPromptNeeded(g);
}

// Shared interception used by both navRun (stdout) and navRunGfx (window):
// help owns the next key, dock Esc saves, dock Q arms the save/quit prompt.
// answer carries the second key only when navQuitKey returned true.
pub fn navIntercept(g: *def.GameState, st: *NavState, dir: []const u8,
    key: input.Key, answer: ?input.Key) NavIntercept {
    navClearFieldMsg(st);
    if (st.help_page != HELP_PAGE_NONE) {
        st.help_page = HELP_PAGE_NONE;
        return NavIntercept{ .handled = true, .quit = false, .msg = "" };
    }
    if (g.screen == def.NAV_DOCK) {
        if (isEsc(key)) {
            const save = save_ux.dockSave(g, dir);
            return NavIntercept{ .handled = true, .quit = false, .msg = save.text };
        }
        if (isChar(key, 'q') and save_ux.quitPromptNeeded(g)) {
            if (answer) |a| {
                const decision = save_ux.quitDecision(g, dir, a.ch);
                return NavIntercept{
                    .handled = true,
                    .quit = decision.quit,
                    .msg = decision.text,
                };
            }
            return NavIntercept{
                .handled = true,
                .quit = false,
                .msg = save_ux.QUIT_PROMPT,
            };
        }
    }
    return NavIntercept{ .handled = false, .quit = false, .msg = "" };
}

// Interactive console loop: render, prompt, read one key, step. EOF exits.
pub fn navRun(g: *def.GameState) void {
    if (g.screen != def.NAV_MAP and g.screen != def.NAV_NODE and g.screen != def.NAV_SETTLE
        and g.screen != def.NAV_SUBDUE_INTRO
        and g.screen != def.NAV_REFINE and g.screen != def.NAV_UPGRADE
        and g.screen != def.NAV_CRAFT and g.screen != def.NAV_BUY and g.screen != def.NAV_TOOLS
        and g.screen != def.NAV_LORE and g.screen != def.NAV_MENU and g.screen != def.NAV_SAVE_ERR
        and g.screen != def.NAV_JOURNAL and g.screen != def.NAV_HELP) {
        g.screen = def.NAV_DOCK;
    }

    var dir_buf: [4096]u8 = undefined;
    const dir = paths.dataDirOrFallback(dir_buf[0..]);
    var st = initState();
    var buf: [8192]u8 = undefined;
    var line_buf: [256]u8 = undefined;

    while (true) {
        io.write(drawCurrent(g, &st, buf[0..]));
        io.write("> ");
        const key = input.readKey() orelse return;

        var answer: ?input.Key = null;
        if (navQuitKey(g, &st, key)) {
            io.write(save_ux.QUIT_PROMPT);
            io.write("\n");
            answer = input.readKey() orelse return;
        }

        const it = navIntercept(g, &st, dir, key, answer);
        if (it.handled) {
            if (it.msg.len > 0) {
                io.write(it.msg);
                io.write("\n");
            }
            if (it.quit) return;
            continue;
        }

        const next = navStep(g, &st, key);
        if (next == def.NAV_QUIT) return;
        const tip = navTipLine(&st);
        if (tip.len > 0) {
            io.write(tip);
            io.write("\n");
        }
        const line = navResultLine(g, &st, line_buf[0..]);
        if (line.len > 0) {
            io.write(line);
            io.write("\n");
        }
    }
}

// Pure boot frame for the shared boot machine (stdout and gfx drivers).
pub fn bootDraw(g: *def.GameState, st: *const NavState, screen: i32,
    sc: *render.Screen) void {
    _ = g;
    if (st.help_page != HELP_PAGE_NONE) {
        const page = journal.helpPage(screen) orelse "(manual text unavailable)";
        render.renderHelp(page, sc);
        return;
    }
    switch (screen) {
        def.NAV_MENU => render.renderMenu(sc),
        def.NAV_LORE => render.renderLore(save_ux.manualPageOne(), sc),
        def.NAV_SAVE_ERR => render.renderSaveError(save_ux.saveErrTextKind(st.save_err_kind), sc),
        else => render.renderLore(save_ux.manualPageOne(), sc),
    }
}

// Pure one-key boot step. `msg` receives the New Game confirmation to show
// BEFORE the next key is read; st.boot_pending remembers that the next key is
// the Y/N answer (no draw/prompt in between, matching the original stdout).
pub fn bootKey(g: *def.GameState, st: *NavState, dir: []const u8,
    screen: i32, key: input.Key, msg: []u8) BootOut {
    var out = BootOut{
        .screen = screen,
        .done = false,
        .quit = false,
        .msg_len = 0,
    };

    if (st.boot_pending != 0) {
        st.boot_pending = 0;
        if (confirmAction(key) != BOOT_ACT_YES) return out;
        game.newGame(g);
        const slot = save_ux.readSaveSlot(dir);
        const saved = save_ux.saveToSlot(g, dir, slot);
        if (!saved.ok) {
            st.save_err_kind = save_ux.ERR_KIND_IO;
            out.screen = def.NAV_SAVE_ERR;
            return out;
        }
        g.screen = def.NAV_DOCK;
        out.screen = def.NAV_DOCK;
        out.done = true;
        return out;
    }

    if (st.help_page != HELP_PAGE_NONE) {
        st.help_page = HELP_PAGE_NONE;
        return out;
    }

    if (screen == def.NAV_MENU) {
        if (key.ch == '?') {
            st.help_page = journal.helpPageNumber(screen);
            return out;
        }
        const act = menuAction(key);
        if (act == BOOT_ACT_CONTINUE) {
            const slot = save_ux.readSaveSlot(dir);
            save_ux.loadSlot(g, dir, slot) catch |e| {
                st.save_err_kind = save_ux.saveErrKind(e);
                out.screen = def.NAV_SAVE_ERR;
                return out;
            };
            g.screen = def.NAV_DOCK;
            out.screen = def.NAV_DOCK;
            out.done = true;
            return out;
        }
        if (act == BOOT_ACT_NEW) {
            st.boot_pending = 1;
            var at: usize = 0;
            text_scan.appendText(msg, &at, save_ux.NEW_GAME_CONFIRM);
            out.msg_len = at;
            return out;
        }
        if (act == BOOT_ACT_OPTIONS) return out;
        if (act == BOOT_ACT_QUIT) {
            out.quit = true;
            return out;
        }
        return out;
    }

    if (screen == def.NAV_LORE) {
        if (key.ch == '?') {
            st.help_page = journal.helpPageNumber(screen);
            return out;
        }
        if (!firstRunAdvance(key)) return out;
        const slot = save_ux.readSaveSlot(dir);
        save_ux.firstRunBeginSlot(g, dir, slot) catch |e| {
            st.save_err_kind = save_ux.saveErrKind(e);
            out.screen = def.NAV_SAVE_ERR;
            return out;
        };
        out.screen = g.screen;
        out.done = true;
        return out;
    }

    if (screen == def.NAV_SAVE_ERR) {
        if (key.ch == '?') {
            st.help_page = journal.helpPageNumber(screen);
            return out;
        }
        const act = errorAction(key);
        if (act == BOOT_ACT_FRESH) {
            save_ux.eraseSlot(dir, save_ux.readSaveSlot(dir));
            out.screen = def.NAV_LORE;
            return out;
        }
        if (act == BOOT_ACT_BACKUP) {
            // Adopt the other slot only after it loads. On failure keep the
            // original failed slot so [F]resh erases the right file.
            const other = save_ux.otherSlot(save_ux.readSaveSlot(dir));
            save_ux.loadSlot(g, dir, other) catch |e| {
                st.save_err_kind = save_ux.saveErrKind(e);
                out.screen = def.NAV_SAVE_ERR;
                return out;
            };
            g.screen = def.NAV_DOCK;
            out.screen = def.NAV_DOCK;
            out.done = true;
            return out;
        }
        if (act == BOOT_ACT_QUIT) {
            out.quit = true;
            return out;
        }
        return out;
    }

    return out;
}

// Shared boot initialisation: reset the GameState, run startup recovery, and
// return the first screen for the active options.cfg slot. Both the stdout
// driver and the gfx driver call this before their own key loops.
pub fn bootReset(g: *def.GameState, dir: []const u8) i32 {
    game.newGame(g);
    persist.recoverAtBoot(dir);
    const slot = save_ux.readSaveSlot(dir);
    return bootStartScreen(save_ux.saveSlotExists(dir, slot));
}

// Boot entry: recovery -> options.cfg slot -> menu when that slot has a save,
// else the §20 first-run flow. Returns true when the dock was reached (the
// caller then runs navRun) and false when the player quits or input ends.
pub fn boot(g: *def.GameState, dir: []const u8) bool {
    // app.zig passes an uninitialised GameState; boot owns the first draw.
    var screen = bootReset(g, dir);
    var st = initState();
    var sc: render.Screen = undefined;
    var buf: [8192]u8 = undefined;
    var msg: [256]u8 = undefined;

    while (true) {
        const pending = st.boot_pending != 0;
        if (!pending) {
            g.screen = screen;
            bootDraw(g, &st, screen, &sc);
            io.write(render.dump(&sc, buf[0..]));
            io.write("> ");
        }

        var key: input.Key = undefined;
        if (!pending and screen == def.NAV_LORE and st.help_page == HELP_PAGE_NONE) {
            key = input.readKeyRaw() orelse return false;
        } else {
            key = input.readKey() orelse return false;
        }

        const out = bootKey(g, &st, dir, screen, key, msg[0..]);
        if (out.msg_len > 0) {
            io.write(msg[0..out.msg_len]);
            io.write("\n");
        }
        screen = out.screen;
        if (out.done) return true;
        if (out.quit) return false;
    }
    return false;
}
