// render_term.zig — UNDERSANDED minimal terminal fight frame (spec §26/§28).
//
// Pure rendering: reads a *GameState + the immutable creature row and writes
// an 80x30 ASCII cell buffer. It never mutates game state, never draws from a
// msg string stored in the log, and never calls into fight.zig beyond reading
// public constants. Console output is plain ASCII (no ANSI), CRLF-safe.
//
// The terminal/console shell can blit `Screen.cells` row by row (std_gfx
// gfxDrawText per row, or std_io text output); native tests inspect `dump()`.

const def = @import("def.zig");
const fight = @import("fight.zig");

pub const COLS: usize = 80;
pub const ROWS: usize = 30;
pub const CELLS: usize = COLS * ROWS;

pub const BAR_WIDTH: i32 = 20;
pub const LOG_LINES: i32 = 8;

pub const Screen = struct { cells: [CELLS]u8 };

const ZERO: u8 = ' ';
const FILL: u8 = '#';
const EMPTY: u8 = '.';

pub fn clear(sc: *Screen) void {
    var i: usize = 0;
    while (i < CELLS) : (i += 1) {
        sc.cells[i] = ZERO;
    }
}

fn putChar(sc: *Screen, x: i32, y: i32, c: u8) void {
    if (x < 0 or y < 0) return;
    const ux: usize = @intCast(usize, x);
    const uy: usize = @intCast(usize, y);
    if (ux >= COLS or uy >= ROWS) return;
    sc.cells[uy * COLS + ux] = c;
}

fn put(sc: *Screen, x: i32, y: i32, text: []const u8) i32 {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        putChar(sc, x + @intCast(i32, i), y, text[i]);
    }
    return x + @intCast(i32, text.len);
}

fn putInt(sc: *Screen, x: i32, y: i32, v: i32) i32 {
    var buf: [12]u8 = undefined;
    const n = intInto(buf[0..], 0, v);
    return put(sc, x, y, buf[0..n]);
}

fn intInto(out: []u8, start: usize, value: i32) usize {
    var p = start;
    var v = value;
    var neg = false;
    if (v < 0) {
        neg = true;
        v = 0 - v;
    }
    var tmp: [12]u8 = undefined;
    var n: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else {
        while (v > 0 and n < tmp.len) {
            tmp[n] = '0' + @intCast(u8, v % 10);
            n += 1;
            v = v / 10;
        }
    }
    if (neg and p < out.len) {
        out[p] = '-';
        p += 1;
    }
    while (n > 0 and p < out.len) {
        n -= 1;
        out[p] = tmp[n];
        p += 1;
    }
    return p;
}

fn copyInto(out: []u8, start: usize, text: []const u8) usize {
    var p = start;
    var i: usize = 0;
    while (i < text.len and p < out.len) : (i += 1) {
        out[p] = text[i];
        p += 1;
    }
    return p;
}

fn barFill(value: i32, max: i32, width: i32) i32 {
    if (max <= 0 or width <= 0) return 0;
    if (value <= 0) return 0;
    if (value >= max) return width;
    var f: i32 = value * width / max;
    if (f < 0) f = 0;
    if (f > width) f = width;
    return f;
}

fn putBar(sc: *Screen, y: i32, label: []const u8, value: i32, max: i32) void {
    var x = put(sc, 0, y, label);
    x = put(sc, x, y, " [");
    const fill = barFill(value, max, BAR_WIDTH);
    var i: i32 = 0;
    while (i < BAR_WIDTH) : (i += 1) {
        if (i < fill) {
            putChar(sc, x + i, y, FILL);
        } else {
            putChar(sc, x + i, y, EMPTY);
        }
    }
    x += BAR_WIDTH;
    x = put(sc, x, y, "] ");
    x = putInt(sc, x, y, value);
    x = put(sc, x, y, "/");
    _ = putInt(sc, x, y, max);
}

pub fn creatureName(id: i32) []const u8 {
    switch (id) {
        1 => return "Mystic Eel",
        2 => return "Mystic Electric Eel",
        4 => return "Steel Tuna",
        18 => return "Anemoniacus",
        19 => return "Freezing Perch",
        else => return "Unknown Creature",
    }
}

// Effective Speed for display: base + stat-threshold bonus + Last Surge
// (+2/surge, capped +6), matching fight.effectiveSpeed for the M2 rows. The
// journal-based hiding rule (§8.8) arrives with journal entries at M8.
pub fn effectiveSpeed(s: *const def.GameState, d: *const def.CreatureDef) i32 {
    var sp = d.speed;

    if (d.speed_below_th > 0) {
        var below: bool = false;
        if (d.speed_below_stat == fight.STAT_RES) {
            below = s.fight.res * 100 < s.fight.max_res * d.speed_below_th;
        } else {
            below = s.fight.hp * 100 < s.fight.max_hp * d.speed_below_th;
        }
        if (below) sp += d.speed_below_add;
    }

    if (s.fight.surge_count > 0) {
        var bonus = s.fight.surge_count * fight.LAST_SURGE_SPEED_ADD;
        if (bonus > fight.LAST_SURGE_SPEED_CAP) bonus = fight.LAST_SURGE_SPEED_CAP;
        sp += bonus;
    }
    return sp;
}

pub fn roleName(role: i32) []const u8 {
    switch (role) {
        1 => return "common",
        2 => return "named",
        3 => return "rare",
        4 => return "boss",
        else => return "unknown",
    }
}

fn msgLine(e: def.LogEntry, d: *const def.CreatureDef, out: []u8) []const u8 {
    var p: usize = 0;
    switch (e.msg_id) {
        fight.MSG_STRIKE => {
            p = copyInto(out, p, "You Strike for ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " HP.");
        },
        fight.MSG_RESTRAIN => {
            p = copyInto(out, p, "You Restrain for ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " Resolve.");
        },
        fight.MSG_CREATURE_ATTACK => {
            p = copyInto(out, p, "Creature hits you for ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " Hull.");
        },
        fight.MSG_SUBDUE_OK => {
            p = copyInto(out, p, "Subdued ");
            p = copyInto(out, p, creatureName(d.id));
            p = copyInto(out, p, " (");
            p = intInto(out, p, d.subdue_chance);
            p = copyInto(out, p, "%).");
        },
        fight.MSG_SUBDUE_FAIL => {
            p = copyInto(out, p, "Subdue failed - ");
            p = copyInto(out, p, creatureName(d.id));
            p = copyInto(out, p, " surges! (");
            p = intInto(out, p, d.subdue_chance);
            p = copyInto(out, p, "%).");
        },
        fight.MSG_KILL => {
            p = copyInto(out, p, "Kill. Overshoot ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " (margin ");
            p = intInto(out, p, e.b);
            p = copyInto(out, p, ").");
        },
        fight.MSG_OVERKILL => {
            p = copyInto(out, p, "Overkill. Overshoot ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " (margin ");
            p = intInto(out, p, e.b);
            p = copyInto(out, p, ").");
        },
        fight.MSG_COUPLING => {
            if (e.b == 2) {
                p = copyInto(out, p, "It recovers ");
                p = intInto(out, p, e.a);
                p = copyInto(out, p, " HP (Despair).");
            } else {
                p = copyInto(out, p, "It recovers ");
                p = intInto(out, p, e.a);
                p = copyInto(out, p, " Resolve (Thrash).");
            }
        },
        fight.MSG_DECLINE => {
            p = copyInto(out, p, "You hold off. Its will begins to recover.");
        },
        fight.MSG_PLAYER_FLED => {
            p = copyInto(out, p, "You flee.");
        },
        fight.MSG_CREATURE_FLED => {
            p = copyInto(out, p, "The creature flees.");
        },
        fight.MSG_EQUIP => {
            p = copyInto(out, p, "You ready tool ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, ".");
        },
        fight.MSG_DISCHARGE => {
            p = copyInto(out, p, "Discharge: ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " Hull.");
        },
        else => {
            if (def.messageText(e.msg_id)) |text| {
                p = copyInto(out, p, text);
            } else if (e.msg_id != 0) {
                p = copyInto(out, p, "Log ");
                p = intInto(out, p, e.msg_id);
                p = copyInto(out, p, ".");
            }
        },
    }
    return out[0..p];
}

fn renderLog(sc: *Screen, s: *const def.GameState, d: *const def.CreatureDef, y0: i32) void {
    var first: i32 = 0;
    if (s.log_n > LOG_LINES) first = s.log_n - LOG_LINES;
    var i: i32 = first;
    var y = y0;
    while (i < s.log_n and y < ROWS) : (i += 1) {
        var buf: [96]u8 = undefined;
        const e = s.log[@intCast(usize, i)];
        const line = msgLine(e, d, buf[0..]);
        _ = put(sc, 0, y, line);
        y += 1;
    }
}

fn renderModal(sc: *Screen, s: *const def.GameState, d: *const def.CreatureDef) void {
    _ = put(sc, 2, 2, "SUBDUE ATTEMPT");
    var x = put(sc, 2, 3, creatureName(d.id));
    x = put(sc, x, 3, " - ");
    x = putInt(sc, x, 3, d.subdue_chance);
    _ = put(sc, x, 3, "% chance");

    _ = put(sc, 2, 5, "Failure triggers a Last Surge: its will");
    _ = put(sc, 2, 6, "partly returns, it hits harder and moves");
    _ = put(sc, 2, 7, "faster. The fight goes on.");

    _ = put(sc, 2, 9, "[A]ttempt   [F] Fight on   [Esc] Cancel");
    _ = s;
}

pub fn renderFrame(s: *const def.GameState, d: *const def.CreatureDef, sc: *Screen) void {
    clear(sc);

    if (s.screen == fight.SCREEN_SUBDUE or s.screen == fight.SCREEN_SUBDUE_POST) {
        renderModal(sc, s, d);
        return;
    }

    _ = put(sc, 0, 0, "UNDERSANDED  FIGHT");

    var x = put(sc, 0, 1, creatureName(d.id));
    x = put(sc, x, 1, "  ");
    x = put(sc, x, 1, roleName(d.role));
    x = put(sc, x, 1, "  SPD ");
    _ = putInt(sc, x, 1, effectiveSpeed(s, d));

    putBar(sc, 3, "HP     ", s.fight.hp, s.fight.max_hp);
    putBar(sc, 4, "RESOLVE", s.fight.res, s.fight.max_res);
    putBar(sc, 5, "HULL   ", s.fight.hull, s.fight.max_hull);

    renderLog(sc, s, d, 7);

    _ = put(sc, 0, 15, "[S]trike [R]estrain [E]quipment [F]lee");
}

// Row-major text dump (trailing spaces trimmed, '\n' after every row) for the
// headless render smoke and future cell-grid goldens.
pub fn dump(sc: *const Screen, out: []u8) []const u8 {
    var p: usize = 0;
    var y: usize = 0;
    while (y < ROWS) : (y += 1) {
        const start = p;
        var x: usize = 0;
        while (x < COLS and p < out.len) : (x += 1) {
            out[p] = sc.cells[y * COLS + x];
            p += 1;
        }
        while (p > start and out[p - 1] == ZERO) p -= 1;
        if (p < out.len) {
            out[p] = 10;
            p += 1;
        }
    }
    return out[0..p];
}
