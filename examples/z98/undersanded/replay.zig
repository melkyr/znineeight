// replay.zig — UNDERSANDED M3 replay v2 text format (spec §28, §34).
//
// The replay is a seed plus an action stream. Ink and encounter draws are not
// recorded; they derive from the seed (§25.5). The pinned grammar is:
//
//   seed=<u32>
//   creature=<token>
//   zone=<text>
//   phase=<text>
//   tool=<text>
//   A <verb>          (one line per action)
//
// `<verb>` is one of strike|restrain|equipment|flee|attempt|decline. F and Esc
// both record as `decline` (§9.3); the recorder owns that dedupe. `creature` is
// an opaque non-empty token here — Task 2's undtool.zig owns token→DEFS-index
// resolution. zone/phase/tool are echoed verbatim and are semantics-free until
// M4/M5.
//
// Tooling module: unlike game.zig it may use std_file/std_io. Pure data +
// text: no fight state is touched.

const def = @import("def.zig");
const file_mod = @import("std_file");
const arena_mod = @import("std_arena");
const str_mod = @import("std_str");
const parse = @import("std_parse");

// ---- Capacities -----------------------------------------------------------

pub const MAX_REPLAY_ACTIONS: usize = 1024;
pub const MAX_TOKEN: usize = 48;
pub const MAX_TEXT: usize = 48;

const WRITE_BUF: usize = 32768;
const READ_BUF: usize = 32768;

pub const Action = def.Action;

// Replay keeps fixed buffers (R1/R8/R14): no slices into the read arena, so
// the value stays valid after replayRead returns.
pub const Replay = struct {
    seed: u32,
    creature: [MAX_TOKEN]u8,
    creature_len: usize,
    zone: [MAX_TEXT]u8,
    zone_len: usize,
    phase: [MAX_TEXT]u8,
    phase_len: usize,
    tool: [MAX_TEXT]u8,
    tool_len: usize,
    acts: [MAX_REPLAY_ACTIONS]Action,
    action_n: usize,
};

pub fn creatureText(r: *const Replay) []const u8 {
    return r.creature[0..r.creature_len];
}

pub fn zoneText(r: *const Replay) []const u8 {
    return r.zone[0..r.zone_len];
}

pub fn phaseText(r: *const Replay) []const u8 {
    return r.phase[0..r.phase_len];
}

pub fn toolText(r: *const Replay) []const u8 {
    return r.tool[0..r.tool_len];
}

pub fn actionSlice(r: *const Replay) []const Action {
    return r.acts[0..r.action_n];
}

// ---- Action verb mapping --------------------------------------------------

fn verbFor(kind: i32) ?[]const u8 {
    switch (kind) {
        def.ACT_STRIKE => return "strike",
        def.ACT_RESTRAIN => return "restrain",
        def.ACT_EQUIP => return "equipment",
        def.ACT_FLEE => return "flee",
        def.ACT_ATTEMPT => return "attempt",
        def.ACT_DECLINE => return "decline",
        else => return null,
    }
}

fn kindForVerb(verb: []const u8) ?i32 {
    if (str_mod.eql(verb, "strike")) return def.ACT_STRIKE;
    if (str_mod.eql(verb, "restrain")) return def.ACT_RESTRAIN;
    if (str_mod.eql(verb, "equipment")) return def.ACT_EQUIP;
    if (str_mod.eql(verb, "flee")) return def.ACT_FLEE;
    if (str_mod.eql(verb, "attempt")) return def.ACT_ATTEMPT;
    if (str_mod.eql(verb, "decline")) return def.ACT_DECLINE;
    return null;
}

// ---- Writer ---------------------------------------------------------------

fn put(buf: []u8, pos: *usize, s: []const u8) bool {
    if (s.len > buf.len - pos.*) return false;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        buf[pos.*] = s[i];
        pos.* += 1;
    }
    return true;
}

fn putChar(buf: []u8, pos: *usize, c: u8) bool {
    if (pos.* >= buf.len) return false;
    buf[pos.*] = c;
    pos.* += 1;
    return true;
}

fn putHeader(buf: []u8, pos: *usize, key: []const u8, value: []const u8) bool {
    if (!put(buf, pos, key)) return false;
    if (!putChar(buf, pos, '=')) return false;
    if (!put(buf, pos, value)) return false;
    return putChar(buf, pos, '\n');
}

pub fn replayWrite(path: []const u8, seed: u32, creature: []const u8, zone: []const u8, phase: []const u8, tool: []const u8, actions: []const Action) bool {
    if (actions.len > MAX_REPLAY_ACTIONS) return false;

    var buf: [WRITE_BUF]u8 = undefined;
    var pos: usize = 0;

    var num_buf: [10]u8 = undefined;
    const seed_text = parse.utoa(num_buf[0..], seed);

    if (!putHeader(buf[0..], &pos, "seed", seed_text)) return false;
    if (!putHeader(buf[0..], &pos, "creature", creature)) return false;
    if (!putHeader(buf[0..], &pos, "zone", zone)) return false;
    if (!putHeader(buf[0..], &pos, "phase", phase)) return false;
    if (!putHeader(buf[0..], &pos, "tool", tool)) return false;

    var i: usize = 0;
    while (i < actions.len) : (i += 1) {
        const verb = verbFor(actions[i].kind) orelse return false;
        if (!put(buf[0..], &pos, "A ")) return false;
        if (!put(buf[0..], &pos, verb)) return false;
        if (!putChar(buf[0..], &pos, '\n')) return false;
    }

    file_mod.writeAll(path, buf[0..pos]) catch return false;
    return true;
}

// ---- Reader ---------------------------------------------------------------

fn initReplay(r: *Replay) void {
    r.seed = 0;
    var i: usize = 0;
    while (i < MAX_TOKEN) : (i += 1) r.creature[i] = 0;
    r.creature_len = 0;
    i = 0;
    while (i < MAX_TEXT) : (i += 1) r.zone[i] = 0;
    r.zone_len = 0;
    i = 0;
    while (i < MAX_TEXT) : (i += 1) r.phase[i] = 0;
    r.phase_len = 0;
    i = 0;
    while (i < MAX_TEXT) : (i += 1) r.tool[i] = 0;
    r.tool_len = 0;
    i = 0;
    while (i < MAX_REPLAY_ACTIONS) : (i += 1) {
        r.acts[i] = Action{ .kind = 0, .arg = 0 };
    }
    r.action_n = 0;
}

fn copyField(dst: []u8, dst_len: *usize, src: []const u8) bool {
    if (src.len == 0) return false;
    if (src.len > dst.len) return false;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[i] = src[i];
    }
    dst_len.* = src.len;
    return true;
}

fn parseActionLine(r: *Replay, line: []const u8) bool {
    if (r.action_n >= MAX_REPLAY_ACTIONS) return false;
    if (line.len < 3) return false;
    if (line[0] != 'A') return false;
    if (line[1] != ' ') return false;

    const kind = kindForVerb(line[2..]) orelse return false;
    r.acts[r.action_n] = Action{ .kind = kind, .arg = 0 };
    r.action_n += 1;
    return true;
}

pub fn replayRead(path: []const u8, out: *Replay) bool {
    var storage: [READ_BUF]u8 = undefined;
    var arena = arena_mod.init(storage[0..]);
    const data = file_mod.readAll(&arena, path) catch return false;

    var tmp: Replay = undefined;
    initReplay(&tmp);

    var pos: usize = 0;
    var header_i: usize = 0;

    while (pos < data.len) {
        var end: usize = pos;
        while (end < data.len and data[end] != '\n') : (end += 1) {}

        var line = data[pos..end];
        pos = end;
        if (pos < data.len) pos += 1;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        if (line.len == 0) continue;

        if (header_i < 5) {
            var kv: str_mod.SplitOnce = undefined;
            if (!str_mod.splitOnce(line, '=', &kv)) return false;

            if (header_i == 0) {
                if (!str_mod.eql(kv.first, "seed")) return false;
                tmp.seed = parse.parseUint(kv.second) orelse return false;
            } else if (header_i == 1) {
                if (!str_mod.eql(kv.first, "creature")) return false;
                if (!copyField(tmp.creature[0..], &tmp.creature_len, kv.second)) return false;
            } else if (header_i == 2) {
                if (!str_mod.eql(kv.first, "zone")) return false;
                if (!copyField(tmp.zone[0..], &tmp.zone_len, kv.second)) return false;
            } else if (header_i == 3) {
                if (!str_mod.eql(kv.first, "phase")) return false;
                if (!copyField(tmp.phase[0..], &tmp.phase_len, kv.second)) return false;
            } else {
                if (!str_mod.eql(kv.first, "tool")) return false;
                if (!copyField(tmp.tool[0..], &tmp.tool_len, kv.second)) return false;
            }
            header_i += 1;
            continue;
        }

        if (!parseActionLine(&tmp, line)) return false;
    }

    if (header_i != 5) return false;

    out.* = tmp;
    return true;
}
