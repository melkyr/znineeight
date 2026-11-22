// journal.zig — UNDERSANDED journal unlock/view state, help pages, tooltips
// (spec §18, §32). Flat masks only; no I/O and no RNG (R1/R2).

const def = @import("def.zig");
const creatures = @import("creatures_t1.zig");
const data = @import("data.zig");

pub const ROLE_BOSS: i32 = 4;

pub const TOOLTIP_RESTRAIN: i32 = 0;
pub const TOOLTIP_RED_ZONE: i32 = 1;

pub const HELP_PAGE_NONE: i32 = 0;

// Nav screen ids from nav.zig, duplicated here so this module never imports
// the navigation loop (which imports journal for its screen hooks).
const SCR_FIGHT: i32 = 0;
const SCR_SUBDUE: i32 = 1;
const SCR_SUBDUE_POST: i32 = 2;
const SCR_DOCK: i32 = 10;
const SCR_MAP: i32 = 11;
const SCR_NODE: i32 = 12;
const SCR_SETTLE: i32 = 13;
const SCR_REFINE: i32 = 14;
const SCR_UPGRADE: i32 = 15;
const SCR_CRAFT: i32 = 16;
const SCR_BUY: i32 = 17;
const SCR_TOOLS: i32 = 18;
const SCR_LORE: i32 = 19;
const SCR_MENU: i32 = 20;
const SCR_SAVE_ERR: i32 = 21;
const SCR_JOURNAL: i32 = 22;
const SCR_HELP: i32 = 23;
const SCR_SUBDUE_INTRO: i32 = 24;
const SCR_SCORE: i32 = 25;
const SCR_CREDITS: i32 = 26;

fn validDefIndex(d: i32) bool {
    if (d < 0) return false;
    return @intCast(usize, d) < creatures.defCount() and d < 64;
}

fn bitOf(d: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, d % 32);
}

fn wordOf(d: i32) usize {
    return @intCast(usize, d / 32);
}

fn maskHas(mask: *const [2]u32, d: i32) bool {
    if (!validDefIndex(d)) return false;
    return (mask[wordOf(d)] & bitOf(d)) != 0;
}

fn maskSet(mask: *[2]u32, d: i32) void {
    if (!validDefIndex(d)) return;
    mask[wordOf(d)] = mask[wordOf(d)] | bitOf(d);
}

fn maskClear(mask: *[2]u32, d: i32) void {
    if (!validDefIndex(d)) return;
    mask[wordOf(d)] = mask[wordOf(d)] & ~bitOf(d);
}

fn isBoss(d: i32) bool {
    if (!validDefIndex(d)) return false;
    return creatures.defAt(d).role == ROLE_BOSS;
}

// First fight end with a non-boss creature unlocks its entry (any outcome:
// kill/overkill/subdue, creature flee, player flee, Hull-0 ascent). The boss
// entry unlocks only through journalOnBossKill (M11).
pub fn journalOnFightEnd(w: *def.World, def_index: i32) void {
    if (!validDefIndex(def_index)) return;
    if (isBoss(def_index)) return;
    if (maskHas(&w.journal_mask, def_index)) return;
    maskSet(&w.journal_mask, def_index);
    maskClear(&w.journal_viewed, def_index);
}

pub fn journalOnBossKill(w: *def.World) void {
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (!isBoss(d)) continue;
        if (maskHas(&w.journal_mask, d)) continue;
        maskSet(&w.journal_mask, d);
        maskClear(&w.journal_viewed, d);
    }
}

pub fn journalUnlocked(w: *const def.World, def_index: i32) bool {
    return maskHas(&w.journal_mask, def_index);
}

pub fn journalViewed(w: *const def.World, def_index: i32) bool {
    return maskHas(&w.journal_viewed, def_index);
}

// Opening an unlocked entry clears its "New entry" marker.
pub fn journalOpen(w: *def.World, def_index: i32) bool {
    if (!journalUnlocked(w, def_index)) return false;
    maskSet(&w.journal_viewed, def_index);
    return true;
}

pub fn journalHasNew(w: *const def.World) bool {
    var d: i32 = 0;
    while (d < creatures.defCount()) : (d += 1) {
        if (!maskHas(&w.journal_mask, d)) continue;
        if (!maskHas(&w.journal_viewed, d)) return true;
    }
    return false;
}

fn appendIntKey(out: []u8, at: *usize, v: i32) void {
    var tmp: [12]u8 = undefined;
    var n: usize = 0;
    var x = v;
    if (x <= 0) {
        if (at.* < out.len) {
            out[at.*] = '0';
            at.* += 1;
        }
        return;
    }
    while (x > 0 and n < tmp.len) {
        tmp[n] = @intCast(u8, '0' + @intCast(i32, x % 10));
        n += 1;
        x = x / 10;
    }
    while (n > 0 and at.* < out.len) {
        n -= 1;
        out[at.*] = tmp[n];
        at.* += 1;
    }
}

// journal.<def_index + 1> in load order (boss = journal.19 at index 18).
pub fn journalKey(def_index: i32, out: []u8) []const u8 {
    var at: usize = 0;
    const prefix: []const u8 = "journal.";
    var i: usize = 0;
    while (i < prefix.len and at < out.len) : (i += 1) {
        out[at] = prefix[i];
        at += 1;
    }
    appendIntKey(out, &at, def_index + 1);
    return out[0..at];
}

// Page map (spec §7.1): dock 1, map/node 5, fight/subdue 2, subdue intro and
// settle 3, refine/upgrade 4, craft/tools 6, journal 9, buy/score/credits 8.
// Everything else falls back to page 1 so `?` works on every screen. Returns
// the manual page number (never zero).
pub fn helpPageNumber(screen: i32) i32 {
    switch (screen) {
        SCR_DOCK => return 1,
        SCR_MAP => return 5,
        SCR_NODE => return 5,
        SCR_FIGHT, SCR_SUBDUE, SCR_SUBDUE_POST => return 2,
        SCR_SETTLE, SCR_SUBDUE_INTRO => return 3,
        SCR_REFINE, SCR_UPGRADE => return 4,
        SCR_CRAFT, SCR_TOOLS => return 6,
        SCR_JOURNAL => return 9,
        SCR_BUY, SCR_SCORE, SCR_CREDITS => return 8,
        SCR_LORE, SCR_MENU, SCR_SAVE_ERR, SCR_HELP => return 1,
        else => return 1,
    }
}

pub fn helpPage(screen: i32) ?[]const u8 {
    const page = helpPageNumber(screen);
    var key_buf: [16]u8 = undefined;
    var at: usize = 0;
    const prefix: []const u8 = "manual.";
    var i: usize = 0;
    while (i < prefix.len and at < key_buf.len) : (i += 1) {
        key_buf[at] = prefix[i];
        at += 1;
    }
    appendIntKey(key_buf[0..], &at, page);
    return data.textFind(key_buf[0..at]);
}

fn tooltipBit(kind: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, kind);
}

pub fn tooltip(kind: i32) ?[]const u8 {
    switch (kind) {
        TOOLTIP_RESTRAIN => return "Restrain damages Resolve, not HP.",
        TOOLTIP_RED_ZONE => return "Past the red zone is overkill. It costs you the rare.",
        else => return null,
    }
}

pub fn tooltipShown(w: *const def.World, kind: i32) bool {
    if (kind < 0 or kind > 1) return false;
    return (w.tooltip_shown & tooltipBit(kind)) != 0;
}

// First occurrence only: returns the copy and records it, or null when the
// tooltip was already shown this install.
pub fn tooltipShow(w: *def.World, kind: i32) ?[]const u8 {
    if (tooltipShown(w, kind)) return null;
    const text = tooltip(kind) orelse return null;
    w.tooltip_shown = w.tooltip_shown | tooltipBit(kind);
    return text;
}
