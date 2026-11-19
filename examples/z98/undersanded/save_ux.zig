// save_ux.zig — UNDERSANDED M7 save UX + first run (spec §20, §32, §33).
//
// Pure decision helpers plus the small amount of file I/O the UX owns: the
// read-only options.cfg slot reader, the Esc-at-dock save, and the fresh-install
// initial save (world initialization, never an autosave).

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const def = @import("def.zig");
const game = @import("game.zig");
const persist = @import("persist.zig");

pub const QUIT_PROMPT: []const u8 = "Save before quitting? [Y] [N] [Cancel]";
pub const SAVE_ERROR_KEYS: []const u8 = "[F]resh  [B]ackup slot  [Q]uit";
pub const SAVE_OK: []const u8 = "Saved.";
pub const SAVE_FAILED: []const u8 = "Save failed.";
pub const MANUAL_KEY: []const u8 = "manual.1";
pub const MANUAL_UNAVAILABLE: []const u8 = "(manual text unavailable)";
pub const SAVE0_FILE: []const u8 = "save0.dat";
pub const SAVE1_FILE: []const u8 = "save1.dat";
pub const OPTIONS_FILE: []const u8 = "options.cfg";
pub const FIRST_RUN_DONE_SCREEN: i32 = 10;

pub const SaveOutcome = struct { ok: bool, text: []const u8 };

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

fn findEq(line: []const u8) ?usize {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '=') return i;
    }
    return null;
}

fn join(dir: []const u8, name: []const u8, out: []u8) ?[]const u8 {
    var sep: u8 = '/';
    if (@isWindows()) sep = '\\';

    var add_sep = false;
    if (dir.len > 0) {
        const last = dir[dir.len - 1];
        if (last != '\\' and last != '/') add_sep = true;
    }

    var need: usize = dir.len + name.len;
    if (add_sep) need += 1;
    if (need > out.len) return null;

    var o: usize = 0;
    var i: usize = 0;
    while (i < dir.len) : (i += 1) {
        out[o] = dir[i];
        o += 1;
    }
    if (add_sep) {
        out[o] = sep;
        o += 1;
    }
    i = 0;
    while (i < name.len) : (i += 1) {
        out[o] = name[i];
        o += 1;
    }
    return out[0..need];
}

fn isPending(g: *const def.GameState) bool {
    return g.fight.outcome == def.OUT_SUBDUE and g.fight.def_index != def.NO_FIGHT;
}

// null means saving is allowed; otherwise the greyed reason is returned.
pub fn canSave(g: *const def.GameState) ?[]const u8 {
    if (g.fight.def_index != def.NO_FIGHT and g.fight.outcome == def.OUT_ONGOING) {
        return "Cannot save during a fight.";
    }
    if (isPending(g)) return "Cannot save while a Release/Sell choice is pending.";
    return null;
}

// The P25/R1 block is the only time the dock quit prompt is skipped; at the
// dock canSave is otherwise always allowed.
pub fn quitPromptNeeded(g: *const def.GameState) bool {
    return canSave(g) == null;
}

pub fn saveErrText(e: persist.SaveErr) []const u8 {
    switch (e) {
        error.Missing => return "Save file is missing.",
        error.BadVersion => return "Save is from a different version.",
        error.BadDataVersion => return "Save is from different content.",
        error.BadHash => return "Save file is damaged.",
        error.BadId => return "Save file references unknown content.",
        error.Damaged => return "Save file is damaged.",
        else => return SAVE_FAILED,
    }
}

// M6 authors manual.1; M7 only consumes the installed Tables.
pub fn manualPageOne() []const u8 {
    const t = def.content_override orelse return MANUAL_UNAVAILABLE;
    if (t.text_count <= 0) return MANUAL_UNAVAILABLE;
    var i: usize = 0;
    while (i < @intCast(usize, t.text_count)) : (i += 1) {
        if (eql(t.text_key[i], MANUAL_KEY)) return t.text_val[i];
    }
    return MANUAL_UNAVAILABLE;
}

pub fn saveSlotName(slot: i32) []const u8 {
    if (slot == 1) return SAVE1_FILE;
    return SAVE0_FILE;
}

pub fn saveSlotPath(dir: []const u8, slot: i32, out: []u8) ?[]const u8 {
    return join(dir, saveSlotName(slot), out);
}

pub fn activeSavePath(dir: []const u8, out: []u8) ?[]const u8 {
    return saveSlotPath(dir, readSaveSlot(dir), out);
}

// Read-only options.cfg key save_slot=0|1. Absent/damaged defaults to slot 0;
// M12 owns writing this file.
pub fn readSaveSlot(dir: []const u8) i32 {
    var path_buf: [4096]u8 = undefined;
    const path = join(dir, OPTIONS_FILE, path_buf[0..]) orelse return 0;
    if (!file_mod.exists(path)) return 0;

    var storage: [16384]u8 = undefined;
    var arena = arena_mod.init(storage[0..]);
    const content = file_mod.readAll(&arena, path) catch return 0;

    var at: usize = 0;
    var slot: i32 = 0;
    var found = false;
    while (at < content.len) {
        const start = at;
        while (at < content.len and content[at] != '\n') : (at += 1) {}
        var line = content[start..at];
        if (at < content.len) at += 1;
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        const t = trim(line);
        if (t.len == 0) continue;
        const eq = findEq(t) orelse continue;
        const key = trim(t[0..eq]);
        if (!eql(key, "save_slot")) continue;
        const val = trim(t[eq + 1 ..]);
        if (eql(val, "0")) {
            slot = 0;
        } else if (eql(val, "1")) {
            slot = 1;
        } else {
            return 0;
        }
        found = true;
    }
    if (!found) return 0;
    return slot;
}

// Esc at the dock: save to the active slot. Blocked/failed saves leave state
// untouched and return the reason/message.
pub fn saveTo(g: *const def.GameState, dir: []const u8) SaveOutcome {
    if (canSave(g)) |reason| return SaveOutcome{ .ok = false, .text = reason };

    var path_buf: [4096]u8 = undefined;
    const path = activeSavePath(dir, path_buf[0..]) orelse {
        return SaveOutcome{ .ok = false, .text = SAVE_FAILED };
    };
    persist.saveWrite(path, &g.world, &g.exp) catch |e| {
        return SaveOutcome{ .ok = false, .text = saveErrText(e) };
    };
    return SaveOutcome{ .ok = true, .text = SAVE_OK };
}

// Fresh install: page 1 -> [Enter] Begin -> world init -> initial save -> dock.
// The save is world initialization, not an autosave, and no menu is shown.
pub fn firstRunBegin(g: *def.GameState, dir: []const u8) persist.SaveErr!void {
    game.newGame(g);
    var path_buf: [4096]u8 = undefined;
    const path = activeSavePath(dir, path_buf[0..]) orelse return persist.SaveErr.Io;
    try persist.saveWrite(path, &g.world, &g.exp);
    g.screen = FIRST_RUN_DONE_SCREEN;
}
