// nav.zig — UNDERSANDED M5 playable console navigation (spec §12, §16, §26).
//
// Pure navigation: navStep maps one key to the next nav screen id and mutates
// game state only through the dock/expedition entry points. All I/O lives in
// navRun (one stdin key per frame); there is no gfx and no RNG of our own.
//
// Nav screen ids live here and stay disjoint from fight.SCREEN_* (0..2).
// GameState.screen carries the nav id while navigating; fight.zig overwrites
// it with SCREEN_FIGHT/SCREEN_SUBDUE when a fight starts.
//
// UI-only state (the rare-batch two-press confirm and the last dock result)
// lives in NavState, never GameState (R16).

const io = @import("std_io.zig");
const def = @import("def.zig");
const input = @import("input.zig");
const expedition = @import("expedition.zig");
const creatures = @import("creatures_t1.zig");
const dock = @import("dock.zig");
const render = @import("render_term.zig");
const paths = @import("paths.zig");
const save_ux = @import("save_ux.zig");
const game = @import("game.zig");
const persist = @import("persist.zig");
const journal = @import("journal.zig");
const fight = @import("fight.zig");

pub const NAV_DOCK: i32 = 10;
pub const NAV_MAP: i32 = 11;
pub const NAV_NODE: i32 = 12;
pub const NAV_SETTLE: i32 = 13;
pub const NAV_REFINE: i32 = 14;
pub const NAV_UPGRADE: i32 = 15;
pub const NAV_CRAFT: i32 = 16;
pub const NAV_BUY: i32 = 17;
pub const NAV_TOOLS: i32 = 18;
pub const NAV_LORE: i32 = 19;
pub const NAV_MENU: i32 = 20;
pub const NAV_SAVE_ERR: i32 = 21;
pub const NAV_JOURNAL: i32 = 22;
pub const NAV_HELP: i32 = 23;
pub const NAV_QUIT: i32 = -1;

pub const NAV_RESULT_NONE: i32 = -100;
pub const NAV_RESULT_PREVIEW: i32 = -101;

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
    if (save_exists) return NAV_MENU;
    return NAV_LORE;
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

fn dockStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    st.armed = 0;
    if (isChar(key, 'q')) return NAV_QUIT;
    if (isChar(key, 'd')) return setScreen(g, NAV_MAP);
    if (isChar(key, 't')) expedition.restAtDock(g);
    if (isChar(key, 'r')) return setScreen(g, NAV_REFINE);
    if (isChar(key, 'u')) return setScreen(g, NAV_UPGRADE);
    if (isChar(key, 'c')) return setScreen(g, NAV_CRAFT);
    if (isChar(key, 'b')) return setScreen(g, NAV_BUY);
    if (isChar(key, 'e')) return setScreen(g, NAV_TOOLS);
    return setScreen(g, NAV_DOCK);
}

// Refine sub-menu: common parts execute on one press; Glow Polyp (6) and Glass
// Pane (7) arm a rare-batch preview and execute on the same key again. Any
// other key cancels the arm; Esc backs out to the dock (R11/P22.9).
fn refineStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) {
        st.armed = 0;
        return setScreen(g, NAV_DOCK);
    }

    if (key.ch >= '1' and key.ch <= '7') {
        const material: i32 = @intCast(i32, key.ch - '0');
        if (st.armed != 0 and st.armed != material) {
            st.armed = 0;
            return setScreen(g, NAV_REFINE);
        }
        if (dock.isRareRefine(material) and st.armed != material
            and dock.refineParts(g, material) > 0) {
            st.armed = material;
            st.last = NAV_RESULT_PREVIEW;
            return setScreen(g, NAV_REFINE);
        }
        st.armed = 0;
        st.last = dock.dockRefine(g, material);
        return setScreen(g, NAV_REFINE);
    }

    // Any other key cancels a pending rare-batch confirm.
    st.armed = 0;
    return setScreen(g, NAV_REFINE);
}

fn upgradeStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, NAV_DOCK);
    if (key.ch >= '1' and key.ch <= '5') {
        const axis: i32 = @intCast(i32, key.ch - '1');
        st.last = dock.dockUpgrade(g, axis);
    }
    return setScreen(g, NAV_UPGRADE);
}

fn craftStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, NAV_DOCK);
    if (key.ch >= '1' and key.ch <= '7') {
        const tool: i32 = @intCast(i32, key.ch - '0');
        st.last = dock.dockCraft(g, tool);
    }
    return setScreen(g, NAV_CRAFT);
}

fn buyStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, NAV_DOCK);
    const c = lower(key.ch);
    if (c >= '1' and c <= '9') {
        const cosmetic: i32 = @intCast(i32, c - '1');
        st.last = dock.dockBuy(g, cosmetic);
    } else if (c >= 'a' and c <= 'c') {
        const cosmetic: i32 = @intCast(i32, 9 + (c - 'a'));
        st.last = dock.dockBuy(g, cosmetic);
    }
    return setScreen(g, NAV_BUY);
}

fn toolsStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (isEsc(key)) return setScreen(g, NAV_DOCK);
    if (isChar(key, '0')) {
        st.last = dock.dockSelectTool(g, 0);
    } else if (key.ch >= '1' and key.ch <= '7') {
        const tool: i32 = @intCast(i32, key.ch - '0');
        st.last = dock.dockSelectTool(g, tool);
    }
    return setScreen(g, NAV_TOOLS);
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

fn journalStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    if (st.journal_sel > 0) {
        if (isEsc(key)) st.journal_sel = 0;
        return setScreen(g, NAV_JOURNAL);
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
    return setScreen(g, NAV_JOURNAL);
}

// Next screen id for one key. Mutates game state only via dock/expedition.
pub fn navStep(g: *def.GameState, st: *NavState, key: input.Key) i32 {
    st.last = NAV_RESULT_NONE;
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
        // Keep fight.zig's SCREEN_* while the fight runs; only an ended fight
        // hands the screen back to nav.
        return setScreen(g, screenAfterField(g));
    }

    // `J` opens the Journal everywhere but mid-fight (including settle/submenus).
    if (isChar(key, 'j') and g.screen != NAV_JOURNAL) {
        st.journal_sel = 0;
        return setScreen(g, NAV_JOURNAL);
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

    // (3) Field and dock sub-menu screens. An uninitialised screen id is
    // treated as the dock.
    switch (g.screen) {
        NAV_MAP => return mapStep(g, key),
        NAV_NODE => return nodeStep(g, key),
        NAV_REFINE => return refineStep(g, st, key),
        NAV_UPGRADE => return upgradeStep(g, st, key),
        NAV_CRAFT => return craftStep(g, st, key),
        NAV_BUY => return buyStep(g, st, key),
        NAV_TOOLS => return toolsStep(g, st, key),
        NAV_LORE => return setScreen(g, NAV_LORE),
        NAV_MENU => return setScreen(g, NAV_MENU),
        NAV_SAVE_ERR => return setScreen(g, NAV_SAVE_ERR),
        NAV_JOURNAL => return journalStep(g, st, key),
        NAV_HELP => return setScreen(g, NAV_HELP),
        else => return dockStep(g, st, key),
    }
}

pub fn drawCurrent(g: *def.GameState, st: *const NavState, out: []u8) []const u8 {
    var sc: render.Screen = undefined;
    if (st.help_page != HELP_PAGE_NONE) {
        const page = journal.helpPage(g.screen) orelse "(manual text unavailable)";
        render.renderHelp(page, &sc);
        return render.dump(&sc, out);
    }
    if (expedition.isInFight(g)) {
        var d = creatures.defAt(g.fight.def_index);
        render.renderFrame(g, &d, &sc);
    } else switch (g.screen) {
        NAV_MAP => render.renderMap(g, &sc),
        NAV_NODE, NAV_SETTLE => render.renderNode(g, &sc),
        NAV_REFINE => render.renderRefine(g, &sc),
        NAV_UPGRADE => render.renderUpgrade(g, &sc),
        NAV_CRAFT => render.renderCraft(g, &sc),
        NAV_BUY => render.renderBuy(g, &sc),
        NAV_TOOLS => render.renderTools(g, &sc),
        NAV_LORE => render.renderLore(save_ux.manualPageOne(), &sc),
        NAV_MENU => render.renderMenu(&sc),
        NAV_SAVE_ERR => render.renderSaveError(save_ux.saveErrTextKind(st.save_err_kind), &sc),
        NAV_JOURNAL => render.renderJournal(g, st.journal_sel, &sc),
        NAV_HELP => {
            const page = journal.helpPage(g.screen) orelse "(manual text unavailable)";
            render.renderHelp(page, &sc);
        },
        else => render.renderDock(g, &sc),
    }
    return render.dump(&sc, out);
}

fn writeRarePreview(g: *def.GameState, st: *const NavState) void {
    const parts = dock.refineParts(g, st.armed);
    const total = parts * dock.refinePerPart(g, st.armed);
    io.write("Rare batch: ");
    io.printInt(parts);
    io.write(" parts -> ");
    io.printInt(total);
    io.write(" materials (expertise +1). Press again to confirm; Esc cancels.\n");
}

// Interactive console loop: render, prompt, read one key, step. EOF exits.
pub fn navRun(g: *def.GameState) void {
    if (g.screen != NAV_MAP and g.screen != NAV_NODE and g.screen != NAV_SETTLE
        and g.screen != NAV_REFINE and g.screen != NAV_UPGRADE
        and g.screen != NAV_CRAFT and g.screen != NAV_BUY and g.screen != NAV_TOOLS
        and g.screen != NAV_LORE and g.screen != NAV_MENU and g.screen != NAV_SAVE_ERR
        and g.screen != NAV_JOURNAL and g.screen != NAV_HELP) {
        g.screen = NAV_DOCK;
    }

    var dir_buf: [4096]u8 = undefined;
    const dir = paths.dataDirOrFallback(dir_buf[0..]);
    var st = NavState{
        .armed = 0,
        .last = NAV_RESULT_NONE,
        .save_err_kind = save_ux.ERR_KIND_NONE,
        .help_page = HELP_PAGE_NONE,
        .tip = TIP_NONE,
        .journal_sel = 0,
    };
    var buf: [8192]u8 = undefined;

    while (true) {
        io.write(drawCurrent(g, &st, buf[0..]));
        io.write("> ");
        const key = input.readKey() orelse return;

        // A help overlay owns the next key: dismiss it and consume the key
        // before the dock save/quit intercept or any field action can run.
        if (st.help_page != HELP_PAGE_NONE) {
            st.help_page = HELP_PAGE_NONE;
            continue;
        }

        if (g.screen == NAV_DOCK) {
            if (isEsc(key)) {
                const save = save_ux.dockSave(g, dir);
                io.write(save.text);
                io.write("\n");
                continue;
            }
            if (isChar(key, 'q') and save_ux.quitPromptNeeded(g)) {
                io.write(save_ux.QUIT_PROMPT);
                io.write("\n");
                const answer = input.readKey() orelse return;
                const decision = save_ux.quitDecision(g, dir, answer.ch);
                if (decision.text.len > 0) {
                    io.write(decision.text);
                    io.write("\n");
                }
                if (decision.quit) return;
                continue;
            }
        }

        const next = navStep(g, &st, key);
        if (next == NAV_QUIT) return;
        if (st.tip != TIP_NONE) {
            if (journal.tooltip(st.tip - 1)) |tip| {
                io.write(tip);
                io.write("\n");
            }
        }
        if (st.last >= 0) {
            io.write(dock.resultText(st.last));
            io.write("\n");
        } else if (st.last == NAV_RESULT_PREVIEW) {
            writeRarePreview(g, &st);
        }
    }
}

// Boot entry: recovery -> options.cfg slot -> menu when that slot has a save,
// else the §20 first-run flow. Returns true when the dock was reached (the
// caller then runs navRun) and false when the player quits or input ends.
pub fn boot(g: *def.GameState, dir: []const u8) bool {
    // app.zig passes an uninitialised GameState; boot owns the first draw.
    game.newGame(g);
    persist.recoverAtBoot(dir);

    var slot = save_ux.readSaveSlot(dir);
    var screen = bootStartScreen(save_ux.saveSlotExists(dir, slot));
    var st = NavState{
        .armed = 0,
        .last = NAV_RESULT_NONE,
        .save_err_kind = save_ux.ERR_KIND_NONE,
        .help_page = HELP_PAGE_NONE,
        .tip = TIP_NONE,
        .journal_sel = 0,
    };
    var buf: [8192]u8 = undefined;

    while (true) {
        g.screen = screen;
        io.write(drawCurrent(g, &st, buf[0..]));

        // `?` works on the boot screens too; any key dismisses the page and
        // returns to the same screen without taking a menu/first-run action.
        if (st.help_page != HELP_PAGE_NONE) {
            io.write("> ");
            _ = input.readKey() orelse return false;
            st.help_page = HELP_PAGE_NONE;
            continue;
        }

        if (screen == NAV_MENU) {
            io.write("> ");
            const key = input.readKey() orelse return false;
            if (key.ch == '?') {
                st.help_page = journal.helpPageNumber(screen);
                continue;
            }
            const act = menuAction(key);
            if (act == BOOT_ACT_CONTINUE) {
                save_ux.loadSlot(g, dir, slot) catch |e| {
                    st.save_err_kind = save_ux.saveErrKind(e);
                    screen = NAV_SAVE_ERR;
                    continue;
                };
                g.screen = NAV_DOCK;
                return true;
            }
            if (act == BOOT_ACT_NEW) {
                io.write(save_ux.NEW_GAME_CONFIRM);
                io.write("\n");
                const answer = input.readKey() orelse return false;
                if (confirmAction(answer) != BOOT_ACT_YES) continue;
                game.newGame(g);
                const out = save_ux.saveToSlot(g, dir, slot);
                if (!out.ok) {
                    st.save_err_kind = save_ux.ERR_KIND_IO;
                    screen = NAV_SAVE_ERR;
                    continue;
                }
                g.screen = NAV_DOCK;
                return true;
            }
            if (act == BOOT_ACT_OPTIONS) continue;
            if (act == BOOT_ACT_QUIT) return false;
            continue;
        }

        if (screen == NAV_LORE) {
            io.write("> ");
            const key = input.readKeyRaw() orelse return false;
            if (key.ch == '?') {
                st.help_page = journal.helpPageNumber(screen);
                continue;
            }
            if (!firstRunAdvance(key)) continue;
            save_ux.firstRunBeginSlot(g, dir, slot) catch |e| {
                st.save_err_kind = save_ux.saveErrKind(e);
                screen = NAV_SAVE_ERR;
                continue;
            };
            return true;
        }

        if (screen == NAV_SAVE_ERR) {
            io.write("> ");
            const key = input.readKey() orelse return false;
            if (key.ch == '?') {
                st.help_page = journal.helpPageNumber(screen);
                continue;
            }
            const act = errorAction(key);
            if (act == BOOT_ACT_FRESH) {
                save_ux.eraseSlot(dir, slot);
                screen = NAV_LORE;
                continue;
            }
            if (act == BOOT_ACT_BACKUP) {
                // Adopt the other slot only after it loads. On failure keep the
                // original failed slot so [F]resh erases the right file.
                const other = save_ux.otherSlot(slot);
                save_ux.loadSlot(g, dir, other) catch |e| {
                    st.save_err_kind = save_ux.saveErrKind(e);
                    screen = NAV_SAVE_ERR;
                    continue;
                };
                slot = other;
                g.screen = NAV_DOCK;
                return true;
            }
            if (act == BOOT_ACT_QUIT) return false;
            continue;
        }

        screen = bootStartScreen(save_ux.saveSlotExists(dir, slot));
    }
    return false;
}
