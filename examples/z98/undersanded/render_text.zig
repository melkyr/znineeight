// render_text.zig — shared terminal cell canvas and copy renderers.
//
// Pure text: no game-state mutation and no I/O. render_term and render_art
// consume this module so the fight log, tool status, subdue modal and help
// copy have one owner.

const def = @import("def.zig");
const fight = @import("fight.zig");
const items = @import("items.zig");
const tools = @import("tools.zig");
const creatures = @import("creatures_t1.zig");

pub const COLS: usize = 80;
pub const ROWS: usize = 30;
pub const CELLS: usize = COLS * ROWS;

pub const Screen = struct { cells: [CELLS]u8 };

const ZERO: u8 = ' ';

pub fn clear(sc: *Screen) void {
    var i: usize = 0;
    while (i < CELLS) : (i += 1) {
        sc.cells[i] = ZERO;
    }
}

pub fn putChar(sc: *Screen, x: i32, y: i32, c: u8) void {
    if (x < 0 or y < 0) return;
    const ux: usize = @intCast(usize, x);
    const uy: usize = @intCast(usize, y);
    if (ux >= COLS or uy >= ROWS) return;
    sc.cells[uy * COLS + ux] = c;
}

pub fn put(sc: *Screen, x: i32, y: i32, text: []const u8) i32 {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        putChar(sc, x + @intCast(i32, i), y, text[i]);
    }
    return x + @intCast(i32, text.len);
}

pub fn putInt(sc: *Screen, x: i32, y: i32, v: i32) i32 {
    var buf: [12]u8 = undefined;
    const n = intInto(buf[0..], 0, v);
    return put(sc, x, y, buf[0..n]);
}

pub fn intInto(out: []u8, start: usize, value: i32) usize {
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

pub fn copyInto(out: []u8, start: usize, text: []const u8) usize {
    var p = start;
    var i: usize = 0;
    while (i < text.len and p < out.len) : (i += 1) {
        out[p] = text[i];
        p += 1;
    }
    return p;
}

pub fn keyIntInto(prefix: []const u8, n: i32, out: []u8) []const u8 {
    var p = copyInto(out, 0, prefix);
    p = intInto(out, p, n);
    return out[0..p];
}

fn journalMaskHas(s: *const def.GameState, d: i32) bool {
    if (d < 0 or d >= 64) return false;
    const word: usize = @intCast(usize, d / 32);
    const bit: u32 = @intCast(u32, d % 32);
    const m: u32 = @intCast(u32, 1) << bit;
    return (s.world.journal_mask[word] & m) != 0;
}

pub fn speedRevealed(s: *const def.GameState) bool {
    if (journalMaskHas(s, s.fight.def_index)) return true;
    return s.fight.tool_active != 0 and s.fight.tool == def.TOOL_SONAR;
}

pub fn creatureName(d: *const def.CreatureDef) []const u8 {
    return d.name[0..@intCast(usize, d.name_len)];
}

pub fn conditionName(cond: i32) []const u8 {
    switch (cond) {
        def.COND_DROWSY => return "Drowsy",
        def.COND_SHAKY => return "Shaky",
        def.COND_EXPOSED => return "Exposed",
        else => return "none",
    }
}

pub fn conditionEffect(cond: i32) []const u8 {
    switch (cond) {
        def.COND_DROWSY => return "Strike -20%",
        def.COND_SHAKY => return "overkill margin halved",
        def.COND_EXPOSED => return "incoming damage +25%",
        else => return "none",
    }
}

pub fn msgLine(e: def.LogEntry, d: *const def.CreatureDef, out: []u8) []const u8 {
    var p: usize = 0;
    switch (e.msg_id) {
        def.MSG_STRIKE => {
            p = copyInto(out, p, "You Strike for ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " HP.");
        },
        def.MSG_RESTRAIN => {
            p = copyInto(out, p, "You Restrain for ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " Resolve.");
        },
        def.MSG_CREATURE_ATTACK => {
            p = copyInto(out, p, "Creature hits you for ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " Hull.");
        },
        def.MSG_SUBDUE_OK => {
            p = copyInto(out, p, "Subdued ");
            p = copyInto(out, p, creatureName(d));
            p = copyInto(out, p, " (");
            p = intInto(out, p, d.subdue_chance);
            p = copyInto(out, p, "%).");
        },
        def.MSG_SUBDUE_FAIL => {
            p = copyInto(out, p, "Subdue failed - ");
            p = copyInto(out, p, creatureName(d));
            p = copyInto(out, p, " surges! (");
            p = intInto(out, p, d.subdue_chance);
            p = copyInto(out, p, "%).");
        },
        def.MSG_KILL => {
            p = copyInto(out, p, "Kill. Overshoot ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " (margin ");
            p = intInto(out, p, e.b);
            p = copyInto(out, p, ").");
        },
        def.MSG_OVERKILL => {
            p = copyInto(out, p, "Overkill. Overshoot ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " (margin ");
            p = intInto(out, p, e.b);
            p = copyInto(out, p, ").");
        },
        def.MSG_COUPLING => {
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
        def.MSG_DECLINE => {
            p = copyInto(out, p, "You hold off. Its will begins to recover.");
        },
        def.MSG_DECLINE_PLAIN => {
            p = copyInto(out, p, "The creature recovers its footing.");
        },
        def.MSG_PLAYER_FLED => {
            p = copyInto(out, p, "You flee.");
        },
        def.MSG_CREATURE_FLED => {
            p = copyInto(out, p, "The creature flees.");
        },
        def.MSG_EQUIP => {
            p = copyInto(out, p, "You ready tool ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, ".");
        },
        def.MSG_DISCHARGE => {
            p = copyInto(out, p, "Discharge: ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, " Hull.");
        },
        def.MSG_TOOL_BROKEN => {
            p = copyInto(out, p, "Your ");
            p = copyInto(out, p, toolName(e.a));
            p = copyInto(out, p, " breaks - disabled for this expedition.");
        },
        def.MSG_EQUIP_REFUSED => {
            if (e.a == tools.REFUSE_NO_TOOL) {
                p = copyInto(out, p, "No tool selected.");
            } else if (e.a == tools.REFUSE_BROKEN) {
                p = copyInto(out, p, "Tool is broken.");
            } else if (e.a == tools.REFUSE_NO_CHARGE) {
                p = copyInto(out, p, "No charge left.");
            } else if (e.a == tools.REFUSE_RIGGED) {
                p = copyInto(out, p, "Tool is rigged - always on.");
            } else {
                p = copyInto(out, p, "Tool cannot be used.");
            }
        },
        def.MSG_BLIND_ARMED => {
            p = copyInto(out, p, "The creature aims to blind - your next Strike may miss.");
        },
        def.MSG_BLIND => {
            p = copyInto(out, p, "Blinded - your Strike misses.");
        },
        def.MSG_INK_ARMED => {
            p = copyInto(out, p, "Ink clouds the water - your next action may be forced.");
        },
        def.MSG_INK => {
            if (e.a == def.ACT_RESTRAIN) {
                p = copyInto(out, p, "Ink forces you to Restrain.");
            } else if (e.a == def.ACT_EQUIP) {
                p = copyInto(out, p, "Ink forces you to use your tool.");
            } else {
                p = copyInto(out, p, "Ink forces you to Strike.");
            }
        },
        def.MSG_SUPPRESS_LURE => {
            p = copyInto(out, p, "Lure: blind or decoy prevented.");
        },
        def.MSG_SUPPRESS_SONAR => {
            p = copyInto(out, p, "Sonar: ink prevented.");
        },
        def.MSG_SUPPRESS_HOOK => {
            p = copyInto(out, p, "Pressure Hook: flee prevented.");
        },
        def.MSG_SUPPRESS_SHIELD => {
            p = copyInto(out, p, "Coral Shield: discharge prevented.");
        },
        def.MSG_DECOY => {
            p = copyInto(out, p, "Your Strike tears through a decoy.");
        },
        def.MSG_PHASE => {
            p = copyInto(out, p, "The ray phases - your Strike passes through it.");
        },
        def.MSG_LURE => {
            p = copyInto(out, p, "The lure reveals ");
            if (e.a == fight.LURE_REVEAL_DECOY) {
                p = copyInto(out, p, "the real target - the decoy cannot hide.");
            } else if (e.a == fight.PHASE_PHASED) {
                p = copyInto(out, p, "Phase.");
            } else {
                p = copyInto(out, p, "Solid.");
            }
        },
        def.MSG_SONAR => {
            const next = e.b % 10;
            const phase = e.b / 10;
            p = copyInto(out, p, "Sonar: Speed ");
            p = intInto(out, p, e.a);
            p = copyInto(out, p, ", next action ");
            if (next == fight.CREATURE_ACT_FLEE) {
                p = copyInto(out, p, "flee");
            } else {
                p = copyInto(out, p, "attack");
            }
            if ((d.flags & def.F_PHASING) != 0) {
                if (phase == fight.PHASE_PHASED) {
                    p = copyInto(out, p, ", Phase.");
                } else {
                    p = copyInto(out, p, ", Solid.");
                }
            } else {
                p = copyInto(out, p, ".");
            }
        },
        def.MSG_WARY => {
            p = copyInto(out, p, "This one remembers: +15 Resolve.");
        },
        def.MSG_GRUDGE => {
            if (e.a == creatures.GRUDGE_ARMOR) {
                p = copyInto(out, p, "It remembers the last run: +30% armor.");
            } else {
                p = copyInto(out, p, "It remembers the last run: +30 Resolve.");
            }
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

pub fn renderModal(sc: *Screen, s: *const def.GameState, d: *const def.CreatureDef) void {
    _ = put(sc, 2, 2, "SUBDUE ATTEMPT");
    var x = put(sc, 2, 3, creatureName(d));
    x = put(sc, x, 3, " - ");
    x = putInt(sc, x, 3, d.subdue_chance);
    _ = put(sc, x, 3, "% chance");

    x = put(sc, 2, 4, "HP ");
    x = putInt(sc, x, 4, s.fight.hp);
    x = put(sc, x, 4, "/");
    x = putInt(sc, x, 4, s.fight.max_hp);
    x = put(sc, x, 4, "  RES ");
    x = putInt(sc, x, 4, s.fight.res);
    x = put(sc, x, 4, "/");
    x = putInt(sc, x, 4, s.fight.max_res);
    x = put(sc, x, 4, "  HULL ");
    x = putInt(sc, x, 4, s.fight.hull);
    x = put(sc, x, 4, "/");
    _ = putInt(sc, x, 4, s.fight.max_hull);

    _ = put(sc, 2, 6, "Failure triggers a Last Surge:");
    _ = put(sc, 2, 7, "+25% Resolve, +25% Attack, +2 Speed (cap +6).");
    _ = put(sc, 2, 8, "It hits harder and moves faster. The fight goes on.");

    _ = put(sc, 2, 10, "[A] Attempt   [F] Fight on / decline");
    _ = put(sc, 2, 11, "[Esc] Decline");
}

pub fn toolName(id: i32) []const u8 {
    switch (id) {
        1 => return "Steel Plate Tool",
        2 => return "Brine Net",
        3 => return "Electric Gland",
        4 => return "Bioluminescent Lure",
        5 => return "Pressure Hook",
        6 => return "Sonar Ping",
        7 => return "Coral Shield",
        else => return "none",
    }
}

pub fn toolKindName(kind: i32) []const u8 {
    if (kind == def.TOOL_KIND_ACTIVATED) return "activated";
    if (kind == def.TOOL_KIND_RIGGED) return "rigged";
    return "unknown";
}

// One-line in-game effect copy (spec §10/§18); used by Craft and Tools.
pub fn toolEffect(id: i32) []const u8 {
    switch (id) {
        1 => return "Negates armor; halves the Derelict's cannon volley.",
        2 => return "Restrain ignores Shell and phasing reduction.",
        3 => return "Stuns the creature for one turn.",
        4 => return "Reveals phase or the real target; prevents blind and decoy.",
        5 => return "Prevents creature flee.",
        6 => return "Reveals Speed and next action; prevents ink; shows the flip.",
        7 => return "Negates discharge-type Hull damage.",
        else => return "No effect.",
    }
}

pub fn renderToolStatus(sc: *Screen, s: *const def.GameState, y: i32) void {
    var x = put(sc, 0, y, "TOOL  ");
    x = put(sc, x, y, toolName(s.fight.tool));
    x = put(sc, x, y, "  ");
    if (s.fight.tool == 0) {
        x = put(sc, x, y, "none");
    } else {
        x = put(sc, x, y, toolKindName(items.toolKind(s.fight.tool)));
    }
    x = put(sc, x, y, "  charge ");
    x = putInt(sc, x, y, s.fight.tool_charge);
    x = put(sc, x, y, "  broken ");
    if (s.fight.tool_broken != 0) {
        x = put(sc, x, y, "yes");
    } else {
        x = put(sc, x, y, "no");
    }
    x = put(sc, x, y, "  active ");
    if (s.fight.tool_active != 0) {
        _ = put(sc, x, y, "yes");
    } else {
        _ = put(sc, x, y, "no");
    }
}

pub fn putTextBlock(sc: *Screen, y0: i32, text: []const u8, y_limit: i32) void {
    const width: usize = 78;
    var i: usize = 0;
    var y = y0;
    while (i < text.len and y < y_limit) {
        if (text[i] == '\n') {
            if (i + 1 < text.len and text[i + 1] == '\n') {
                y += 2;
                i += 2;
            } else {
                y += 1;
                i += 1;
            }
            continue;
        }

        var line_end = i;
        while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}
        var pos = i;
        while (pos < line_end and y < y_limit) {
            var take = line_end - pos;
            if (take > width) take = width;
            var has_break = false;
            if (pos + take < line_end) {
                var k = take;
                while (k > 0) : (k -= 1) {
                    if (text[pos + k - 1] == ' ') {
                        take = k - 1;
                        has_break = true;
                        break;
                    }
                }
            }
            var k: usize = 0;
            while (k < take) : (k += 1) {
                const c = text[pos + k];
                if (c != '\r') putChar(sc, @intCast(i32, k), y, c);
            }
            pos += take;
            if (has_break and pos < line_end and text[pos] == ' ') pos += 1;
            y += 1;
        }
        i = line_end;
    }
}

pub fn renderHelp(text: []const u8, sc: *Screen) void {
    clear(sc);
    _ = put(sc, 0, 0, "UNDERSANDED  HELP");
    putTextBlock(sc, 2, text, ROWS - 2);
    _ = put(sc, 0, ROWS - 1, "[Any key] Back");
}
