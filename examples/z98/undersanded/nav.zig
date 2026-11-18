// nav.zig — UNDERSANDED M4 playable console navigation (spec §12, §16, §26).
//
// Pure navigation: navStep maps one key to the next nav screen id and mutates
// game state only through the expedition entry points. All I/O lives in
// navRun (one stdin key per frame); there is no gfx and no RNG of our own.
//
// Nav screen ids live here and stay disjoint from fight.SCREEN_* (0..2).
// GameState.screen carries the nav id while navigating; fight.zig overwrites
// it with SCREEN_FIGHT/SCREEN_SUBDUE when a fight starts.

const io = @import("std_io.zig");
const def = @import("def.zig");
const input = @import("input.zig");
const expedition = @import("expedition.zig");
const creatures = @import("creatures_t1.zig");
const render = @import("render_term.zig");

pub const NAV_DOCK: i32 = 10;
pub const NAV_MAP: i32 = 11;
pub const NAV_NODE: i32 = 12;
pub const NAV_SETTLE: i32 = 13;
pub const NAV_QUIT: i32 = -1;

fn lower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

fn isChar(k: input.Key, c: u8) bool {
    return lower(k.ch) == c;
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

// Pending choice -> settle, otherwise an active expedition -> node, else dock.
fn deriveScreen(g: *const def.GameState) i32 {
    if (isPending(g)) return NAV_SETTLE;
    if (g.exp.active != 0) return NAV_NODE;
    return NAV_DOCK;
}

fn setScreen(g: *def.GameState, screen: i32) i32 {
    g.screen = screen;
    return screen;
}

// A field action may start a fight; keep fight.zig's SCREEN_* in that case so
// the next key still maps through input.mapKey.
fn screenAfterField(g: *def.GameState) i32 {
    if (expedition.isInFight(g)) return g.screen;
    return deriveScreen(g);
}

fn dockStep(g: *def.GameState, key: input.Key) i32 {
    if (isChar(key, 'q')) return NAV_QUIT;
    if (isChar(key, 'd')) return setScreen(g, NAV_MAP);
    if (isChar(key, 't')) expedition.restAtDock(g);
    // r/u/c/b print "not yet (M5)" on screen; any other key is a no-op.
    return setScreen(g, NAV_DOCK);
}

fn mapStep(g: *def.GameState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, NAV_DOCK);

    if (key.ch >= '1' and key.ch <= '8') {
        const zone: i32 = @intCast(i32, key.ch - '1');
        _ = expedition.depart(g, zone);
        return setScreen(g, NAV_NODE);
    }

    if (key.ch == '9' and render.bossGateOpen(g)) {
        _ = expedition.depart(g, 8);
        return setScreen(g, NAV_NODE);
    }

    // Locked boss or any other key stays on the map.
    return setScreen(g, NAV_MAP);
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
    return setScreen(g, NAV_NODE);
}

// Next screen id for one key. Mutates game state only via expedition.
pub fn navStep(g: *def.GameState, key: input.Key) i32 {
    // (1) A live fight consumes the key through the fight key map, then the
    // post-fight state decides which nav screen comes next.
    if (expedition.isInFight(g)) {
        if (input.mapKey(g.screen, key)) |act| {
            expedition.expeditionStep(g, act.kind);
        }
        // Keep fight.zig's SCREEN_* while the fight runs; only an ended fight
        // hands the screen back to nav.
        return setScreen(g, screenAfterField(g));
    }

    // (2) A pending Subdue choice must be settled before anything else.
    if (isPending(g)) {
        if (g.screen != NAV_SETTLE) return setScreen(g, NAV_SETTLE);
        if (isChar(key, 'r')) {
            expedition.resolveSubdueChoice(g, expedition.SUB_RELEASE);
        } else if (isChar(key, 's')) {
            expedition.resolveSubdueChoice(g, expedition.SUB_SELL);
        }
        return setScreen(g, deriveScreen(g));
    }

    // (3) Field screens. An uninitialised screen id is treated as the dock.
    switch (g.screen) {
        NAV_MAP => return mapStep(g, key),
        NAV_NODE => return nodeStep(g, key),
        else => return dockStep(g, key),
    }
}

fn drawCurrent(g: *def.GameState, out: []u8) []const u8 {
    var sc: render.Screen = undefined;
    if (expedition.isInFight(g)) {
        var d = creatures.defAt(g.fight.def_index);
        render.renderFrame(g, &d, &sc);
    } else switch (g.screen) {
        NAV_MAP => render.renderMap(g, &sc),
        NAV_NODE, NAV_SETTLE => render.renderNode(g, &sc),
        else => render.renderDock(g, &sc),
    }
    return render.dump(&sc, out);
}

// Interactive console loop: render, prompt, read one key, step. EOF exits.
pub fn navRun(g: *def.GameState) void {
    if (g.screen != NAV_MAP and g.screen != NAV_NODE and g.screen != NAV_SETTLE) {
        g.screen = NAV_DOCK;
    }

    var buf: [8192]u8 = undefined;

    while (true) {
        io.write(drawCurrent(g, buf[0..]));
        io.write("> ");
        const key = input.readKey() orelse return;
        const was_dock = g.screen == NAV_DOCK;
        const next = navStep(g, key);
        if (next == NAV_QUIT) return;
        if (was_dock and next == NAV_DOCK
            and (isChar(key, 'r') or isChar(key, 'u') or isChar(key, 'c') or isChar(key, 'b'))) {
            io.write("Refine, Upgrade, Craft, Buy: not yet (M5).\n");
        }
    }
}
