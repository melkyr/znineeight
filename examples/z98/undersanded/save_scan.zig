// save_scan.zig — UNDERSANDED save scanner and read path (spec §32).
//
// Save-local scanner and section vocabulary (never data.zig's §25.10 parser).
// One scalar `key=value` per line; arrays are one line `name=v,v,...`; [crc32]
// is last and nothing may follow it. Load is all-or-nothing into zeroed temps.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const mem_mod = @import("std_mem.zig");
const parse = @import("std_parse");
const crypto = @import("std_crypto");
const def = @import("def.zig");
const data = @import("data_scan.zig");
const creatures = @import("creatures_t1.zig");
const world = @import("world.zig");
const text_scan = @import("text_scan.zig");

pub const SaveErr = error{ Missing, BadVersion, BadDataVersion, BadHash, BadId, Damaged, Io };

pub const MAX_LINE: usize = 8192;
pub const MAX_FILE: usize = 64 * 1024;

pub const SAVE_VERSION: i32 = 2;


pub const SEC_WORLD: i32 = 0;
pub const SEC_BOAT: i32 = 1;
pub const SEC_COOLDOWNS: i32 = 2;
pub const SEC_JOURNAL: i32 = 3;
pub const SEC_EXPEDITION: i32 = 4;
pub const SEC_SCORE: i32 = 5;
pub const SEC_OPTIONS: i32 = 6;
pub const SEC_CRC: i32 = 7;

pub const WORLD_ALL: u32 = 0x7FFF;
pub const BOAT_ALL: u32 = 0x1;
pub const COOLDOWNS_ALL: u32 = 0x7;
pub const JOURNAL_ALL: u32 = 0x3;
pub const EXPEDITION_ALL: u32 = 0x3FF;
pub const SCORE_ALL: u32 = 0x1FF;
// Known ownership bits: tools 0..7 (MAX_TOOLS=8), cosmetics 0..11.
pub const TOOLS_OWNED_MASK: u32 = 0xFF;
pub const COSMETICS_OWNED_MASK: u32 = 0xFFF;

pub const FIELD_RECORD_LEN: usize = 26;
pub const LAST_RUN_LEN: usize = 6;

var g_arena_buf: [256 * 1024]u8 = undefined;

pub const Line = struct { start: usize, end: usize };

pub fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// Directory portion of a save path (including the trailing separator). Both
// separators are accepted because the deployed target is Win9x.


pub fn nextLine(content: []const u8, at: *usize, out: *Line) bool {
    if (at.* >= content.len) return false;
    const start = at.*;
    var i = start;
    while (i < content.len and content[i] != '\n') : (i += 1) {}
    out.start = start;
    out.end = i;
    if (i < content.len) {
        at.* = i + 1;
    } else {
        at.* = i;
    }
    return true;
}

pub fn sectionId(name: []const u8) i32 {
    if (eql(name, "world")) return SEC_WORLD;
    if (eql(name, "boat")) return SEC_BOAT;
    if (eql(name, "cooldowns")) return SEC_COOLDOWNS;
    if (eql(name, "journal")) return SEC_JOURNAL;
    if (eql(name, "expedition")) return SEC_EXPEDITION;
    if (eql(name, "score")) return SEC_SCORE;
    if (eql(name, "options")) return SEC_OPTIONS;
    if (eql(name, "crc32")) return SEC_CRC;
    return -1;
}

pub fn sectionName(line: []const u8, out: *[]const u8) bool {
    if (line.len < 3) return false;
    if (line[0] != '[' or line[line.len - 1] != ']') return false;
    out.* = line[1 .. line.len - 1];
    return true;
}

pub fn parseScalar(line: []const u8, key: *[]const u8, val: *[]const u8) bool {
    var fields: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 0;
    if (!data.parseRowKV(line, &fields, &n)) return false;
    if (n != 1) return false;
    key.* = fields[0].key;
    val.* = fields[0].val;
    return true;
}

fn parseI32Array(val: []const u8, out: []i32) bool {
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= val.len) : (i += 1) {
        if (i != val.len and val[i] != ',') continue;
        const part = text_scan.trimSpaces(val[start..i]);
        if (part.len == 0) return false;
        if (count >= out.len) return false;
        out[count] = data.parseI32(part) orelse return false;
        count += 1;
        start = i + 1;
    }
    return count == out.len;
}

fn parseU32Array(val: []const u8, out: []u32) bool {
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= val.len) : (i += 1) {
        if (i != val.len and val[i] != ',') continue;
        const part = text_scan.trimSpaces(val[start..i]);
        if (part.len == 0) return false;
        if (count >= out.len) return false;
        out[count] = parse.parseUint(part) orelse return false;
        count += 1;
        start = i + 1;
    }
    return count == out.len;
}

fn hexVal(c: u8) i32 {
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(i32, c - 'a') + 10;
    if (c >= 'A' and c <= 'F') return @intCast(i32, c - 'A') + 10;
    return -1;
}

pub fn parseHexU32(s: []const u8) ?u32 {
    if (s.len < 3 or s.len > 10) return null;
    if (s[0] != '0') return null;
    if (s[1] != 'x' and s[1] != 'X') return null;
    var v: u32 = 0;
    var i: usize = 2;
    while (i < s.len) : (i += 1) {
        const d = hexVal(s[i]);
        if (d < 0) return null;
        v = v * @intCast(u32, 16) + @intCast(u32, d);
    }
    return v;
}

fn markSeen(seen: *[6]u32, sec: usize, bit: u32) bool {
    const m: u32 = @intCast(u32, 1) << bit;
    if ((seen[sec] & m) != 0) return false;
    seen[sec] = seen[sec] | m;
    return true;
}

fn maskBitsValid(mask: *const [2]u32, def_count: i32) bool {
    var d: i32 = def_count;
    while (d < 64) : (d += 1) {
        const word: usize = @intCast(usize, d / 32);
        const bit: u32 = @intCast(u32, d % 32);
        const m: u32 = @intCast(u32, 1) << bit;
        if ((mask[word] & m) != 0) return false;
    }
    return true;
}


pub fn crcOf(prefix: []const u8) u32 {
    return crypto.crc32(prefix);
}

pub fn mapFileError(e: file_mod.FileError) SaveErr {
    if (e == error.OpenFailed) return SaveErr.Io;
    if (e == error.ReadFailed) return SaveErr.Io;
    if (e == error.WriteFailed) return SaveErr.Io;
    if (e == error.SeekFailed) return SaveErr.Io;
    if (e == error.SizeFailed) return SaveErr.Io;
    if (e == error.FlushFailed) return SaveErr.Io;
    if (e == error.RemoveFailed) return SaveErr.Io;
    if (e == error.RenameFailed) return SaveErr.Io;
    if (e == error.OpenDirFailed) return SaveErr.Io;
    if (e == error.ReadDirFailed) return SaveErr.Io;
    if (e == error.OutOfMemory) return SaveErr.Io;
    return SaveErr.Io;
}


fn contentVersion() i32 {
    if (def.content_override) |t| return t.content_version;
    return 2;
}

pub fn saveRead(path: []const u8, w: *def.World, exp: *def.Expedition) SaveErr!void {
    if (!file_mod.exists(path)) return error.Missing;

    var arena = arena_mod.init(g_arena_buf[0..]);
    const content = file_mod.readAll(&arena, path) catch |e| return mapFileError(e);
    if (content.len > MAX_FILE) return error.Damaged;

    var at: usize = 0;
    var line: Line = undefined;
    var section: i32 = -1;
    var next_sec: i32 = 0;
    var saw_version = false;
    var saw_data_version = false;
    var saw_hash = false;
    var crc_start: usize = 0;
    var hash: u32 = 0;

    while (nextLine(content, &at, &line)) {
        const t = text_scan.stripCR(content[line.start..line.end]);
        if (t.len == 0) return error.Damaged;
        if (t.len > MAX_LINE) return error.Damaged;
        if (saw_hash) return error.Damaged;

        if (t[0] == '[') {
            var name: []const u8 = "";
            if (!sectionName(t, &name)) return error.Damaged;
            const sid = sectionId(name);
            if (sid < 0) return error.Damaged;
            if (sid != next_sec) return error.Damaged;
            if (!saw_version or !saw_data_version) return error.Damaged;
            if (sid == SEC_CRC) {
                crc_start = line.start;
            }
            section = sid;
            next_sec = sid + 1;
            continue;
        }

        var key: []const u8 = "";
        var val: []const u8 = "";

        if (section == -1) {
            if (!parseScalar(t, &key, &val)) return error.Damaged;
            if (eql(key, "version")) {
                if (saw_version) return error.Damaged;
                const v = data.parseI32(val) orelse return error.Damaged;
                if (v != SAVE_VERSION) return error.BadVersion;
                saw_version = true;
            } else if (eql(key, "data_version")) {
                if (!saw_version or saw_data_version) return error.Damaged;
                const v = data.parseI32(val) orelse return error.Damaged;
                if (v != contentVersion()) return error.BadDataVersion;
                saw_data_version = true;
            } else {
                return error.Damaged;
            }
            continue;
        }

        if (section == SEC_CRC) {
            if (!parseScalar(t, &key, &val)) return error.Damaged;
            if (!eql(key, "hash")) return error.Damaged;
            hash = parseHexU32(val) orelse return error.Damaged;
            saw_hash = true;
        }
    }

    if (!saw_version or !saw_data_version) return error.Damaged;
    if (next_sec != SEC_CRC + 1 or !saw_hash) return error.Damaged;
    if (crc_start > content.len) return error.Damaged;
    if (crcOf(content[0..crc_start]) != hash) return error.BadHash;

    var tw: def.World = undefined;
    var te: def.Expedition = undefined;
    mem_mod.zeroU8(@ptrCast([*]u8, &tw), @sizeOf(def.World));
    mem_mod.zeroU8(@ptrCast([*]u8, &te), @sizeOf(def.Expedition));

    at = 0;
    section = -1;
    var seen: [6]u32 = [6]u32{ 0, 0, 0, 0, 0, 0 };
    var saw_journal_viewed = false;
    var saw_field_cosmetics = false;

    while (nextLine(content, &at, &line)) {
        const t = text_scan.stripCR(content[line.start..line.end]);
        if (t.len == 0) return error.Damaged;
        if (t[0] == '[') {
            var name: []const u8 = "";
            if (!sectionName(t, &name)) return error.Damaged;
            const sid = sectionId(name);
            if (sid < 0) return error.Damaged;
            if (sid == SEC_CRC) break;
            section = sid;
            continue;
        }
        if (section == -1 or section == SEC_CRC) continue;
        if (section == SEC_OPTIONS) continue;

        const eq = text_scan.findEq(t) orelse return error.Damaged;
        const raw_key = text_scan.trimSpaces(t[0..eq]);
        if (raw_key.len == 0) return error.Damaged;

        if (section == SEC_WORLD) {
            if (eql(raw_key, "seen_mask") or eql(raw_key, "wary_mask")) {
                const val = text_scan.trimSpaces(t[eq + 1 ..]);
                var mask: *[2]u32 = &tw.seen_mask;
                const bit: u32 = if (eql(raw_key, "seen_mask")) 0 else 1;
                if (bit == 1) mask = &tw.wary_mask;
                if (!parseU32Array(val, mask[0..])) return error.Damaged;
                if (!markSeen(&seen, 0, if (bit == 0) 2 else 6)) return error.Damaged;
            } else if (eql(raw_key, "expertise") or eql(raw_key, "materials")) {
                const val = text_scan.trimSpaces(t[eq + 1 ..]);
                const arr: *[def.MAX_MATERIALS]i32 = if (eql(raw_key, "expertise")) &tw.expertise else &tw.materials;
                if (!parseI32Array(val, arr[0..])) return error.Damaged;
                if (!markSeen(&seen, 0, if (eql(raw_key, "expertise")) 9 else 10)) return error.Damaged;
            } else {
                var key: []const u8 = "";
                var val: []const u8 = "";
                if (!parseScalar(t, &key, &val)) return error.Damaged;
                if (eql(key, "cycle")) {
                    tw.cycle = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 0)) return error.Damaged;
                } else if (eql(key, "phase")) {
                    tw.phase = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 1)) return error.Damaged;
                } else if (eql(key, "field_phases")) {
                    tw.field_phases = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 3)) return error.Damaged;
                } else if (eql(key, "hull")) {
                    tw.hull = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 4)) return error.Damaged;
                } else if (eql(key, "family_overkill_mask")) {
                    tw.family_overkill_mask = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 5)) return error.Damaged;
                } else if (eql(key, "rng_state")) {
                    tw.rng_state = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 7)) return error.Damaged;
                } else if (eql(key, "money")) {
                    tw.money = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 8)) return error.Damaged;
                } else if (eql(key, "tools_owned")) {
                    tw.tools_owned = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 11)) return error.Damaged;
                } else if (eql(key, "tool_selected")) {
                    tw.tool_selected = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 12)) return error.Damaged;
                } else if (eql(key, "cosmetics_owned")) {
                    tw.cosmetics_owned = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 13)) return error.Damaged;
                } else if (eql(key, "cosmetics_unlocked")) {
                    tw.cosmetics_unlocked = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 0, 14)) return error.Damaged;
                } else {
                    return error.Damaged;
                }
            }
        } else if (section == SEC_BOAT) {
            const val = text_scan.trimSpaces(t[eq + 1 ..]);
            if (!eql(raw_key, "boat")) return error.Damaged;
            if (!parseI32Array(val, tw.boat[0..])) return error.Damaged;
            if (!markSeen(&seen, 1, 0)) return error.Damaged;
        } else if (section == SEC_COOLDOWNS) {
            const val = text_scan.trimSpaces(t[eq + 1 ..]);
            if (eql(raw_key, "ready")) {
                if (!parseI32Array(val, tw.ready[0..])) return error.Damaged;
                if (!markSeen(&seen, 2, 0)) return error.Damaged;
            } else if (eql(raw_key, "release_bonus")) {
                if (!parseI32Array(val, tw.release_bonus[0..])) return error.Damaged;
                if (!markSeen(&seen, 2, 1)) return error.Damaged;
            } else if (eql(raw_key, "lockout_until")) {
                if (!parseI32Array(val, tw.lockout_until[0..])) return error.Damaged;
                if (!markSeen(&seen, 2, 2)) return error.Damaged;
            } else {
                return error.Damaged;
            }
        } else if (section == SEC_JOURNAL) {
            if (eql(raw_key, "journal_mask")) {
                const val = text_scan.trimSpaces(t[eq + 1 ..]);
                if (!parseU32Array(val, tw.journal_mask[0..])) return error.Damaged;
                if (!markSeen(&seen, 3, 0)) return error.Damaged;
            } else if (eql(raw_key, "journal_viewed")) {
                const val = text_scan.trimSpaces(t[eq + 1 ..]);
                if (saw_journal_viewed) return error.Damaged;
                if (!parseU32Array(val, tw.journal_viewed[0..])) return error.Damaged;
                saw_journal_viewed = true;
            } else {
                var key: []const u8 = "";
                var val: []const u8 = "";
                if (!parseScalar(t, &key, &val)) return error.Damaged;
                if (eql(key, "tooltip_shown")) {
                    tw.tooltip_shown = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 3, 1)) return error.Damaged;
                } else {
                    return error.Damaged;
                }
            }
        } else if (section == SEC_EXPEDITION) {
            if (eql(raw_key, "hold")) {
                const val = text_scan.trimSpaces(t[eq + 1 ..]);
                if (!parseI32Array(val, te.hold[0..])) return error.Damaged;
                if (!markSeen(&seen, 4, 4)) return error.Damaged;
            } else {
                var key: []const u8 = "";
                var val: []const u8 = "";
                if (!parseScalar(t, &key, &val)) return error.Damaged;
                if (eql(key, "active")) {
                    te.active = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 0)) return error.Damaged;
                } else if (eql(key, "zone")) {
                    te.zone = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 1)) return error.Damaged;
                } else if (eql(key, "fight_index")) {
                    te.fight_index = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 2)) return error.Damaged;
                } else if (eql(key, "seed")) {
                    te.seed = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 3)) return error.Damaged;
                } else if (eql(key, "hold_n")) {
                    te.hold_n = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 5)) return error.Damaged;
                } else if (eql(key, "tool")) {
                    te.tool = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 6)) return error.Damaged;
                } else if (eql(key, "tool_charge")) {
                    te.tool_charge = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 7)) return error.Damaged;
                } else if (eql(key, "tool_broken")) {
                    te.tool_broken = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 8)) return error.Damaged;
                } else if (eql(key, "pending_cond")) {
                    te.pending_cond = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 4, 9)) return error.Damaged;
                } else {
                    return error.Damaged;
                }
            }
        } else if (section == SEC_SCORE) {
            if (eql(raw_key, "field_record") or eql(raw_key, "last_run")) {
                const val = text_scan.trimSpaces(t[eq + 1 ..]);
                const fr: *def.FieldRecord = &tw.field_record;
                const lr: *def.LastRun = &tw.last_run;
                if (eql(raw_key, "field_record")) {
                    if (!parseFieldRecord(val, fr)) return error.Damaged;
                    if (!markSeen(&seen, 5, 1)) return error.Damaged;
                } else {
                    if (!parseLastRun(val, lr)) return error.Damaged;
                    if (!markSeen(&seen, 5, 4)) return error.Damaged;
                }
            } else {
                var key: []const u8 = "";
                var val: []const u8 = "";
                if (!parseScalar(t, &key, &val)) return error.Damaged;
                if (eql(key, "field_record_written")) {
                    tw.field_record_written = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 0)) return error.Damaged;
                } else if (eql(key, "boss_variants_seen")) {
                    tw.boss_variants_seen = parse.parseUint(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 2)) return error.Damaged;
                } else if (eql(key, "boss_kills")) {
                    tw.boss_kills = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 3)) return error.Damaged;
                } else if (eql(key, "score_subdued")) {
                    tw.score_subdued = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 5)) return error.Damaged;
                } else if (eql(key, "score_killed")) {
                    tw.score_killed = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 6)) return error.Damaged;
                } else if (eql(key, "score_overkilled")) {
                    tw.score_overkilled = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 7)) return error.Damaged;
                } else if (eql(key, "score_money_earned")) {
                    tw.score_money_earned = data.parseI32(val) orelse return error.Damaged;
                    if (!markSeen(&seen, 5, 8)) return error.Damaged;
                } else if (eql(key, "field_cosmetics")) {
                    if (saw_field_cosmetics) return error.Damaged;
                    tw.field_record.cosmetics_mask =
                        parse.parseUint(val) orelse return error.Damaged;
                    saw_field_cosmetics = true;
                } else {
                    return error.Damaged;
                }
            }
        }
    }

    if (seen[0] != WORLD_ALL or seen[1] != BOAT_ALL or seen[2] != COOLDOWNS_ALL) {
        return error.Damaged;
    }
    if (seen[3] != JOURNAL_ALL or seen[4] != EXPEDITION_ALL or seen[5] != SCORE_ALL) {
        return error.Damaged;
    }

    const def_count = creatures.defCount();

    if (tw.phase != 0 and tw.phase != 1) return error.Damaged;

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        if (tw.boat[i] < 0 or tw.boat[i] > 3) return error.Damaged;
    }
    if (tw.hull < 0 or tw.hull > world.HULL_TABLE[@intCast(usize, tw.boat[world.BOAT_HULL])]) {
        return error.Damaged;
    }

    i = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        if (tw.expertise[i] < 0 or tw.expertise[i] > 5) return error.Damaged;
        if (tw.materials[i] < 0) return error.Damaged;
    }
    if (tw.money < 0) return error.Damaged;
    if (tw.tool_selected < 0 or tw.tool_selected > 7) return error.Damaged;
    if (te.hold_n < 0 or te.hold_n > def.MAX_PARTS) return error.Damaged;

    // Crafted-but-CRC-valid states still have to pass the same vocabulary the
    // rest of the game assumes.
    if (te.active != 0 and te.active != 1) return error.Damaged;
    if (te.zone < 0 or te.zone >= @intCast(i32, def.MAX_ZONES)) return error.Damaged;
    if (te.fight_index < 0) return error.Damaged;
    if (te.tool < 0 or te.tool > 7) return error.Damaged;
    if (te.tool_charge < 0) return error.Damaged;
    if (te.tool_broken < 0 or te.tool_broken > 1) return error.Damaged;
    if (te.pending_cond < def.COND_NONE or te.pending_cond > def.COND_EXPOSED) return error.Damaged;
    i = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (te.hold[i] < 0) return error.Damaged;
    }
    if (tw.boss_variants_seen > 31) return error.Damaged;
    if ((tw.tools_owned & ~TOOLS_OWNED_MASK) != 0) return error.Damaged;
    if ((tw.cosmetics_owned & ~COSMETICS_OWNED_MASK) != 0) return error.Damaged;
    if ((tw.cosmetics_unlocked & ~COSMETICS_OWNED_MASK) != 0) return error.Damaged;
    if ((tw.field_record.cosmetics_mask & ~COSMETICS_OWNED_MASK) != 0) {
        return error.Damaged;
    }

    if (!maskBitsValid(&tw.seen_mask, def_count)) return error.BadId;
    if (!maskBitsValid(&tw.journal_mask, def_count)) return error.BadId;
    if (!maskBitsValid(&tw.journal_viewed, def_count)) return error.BadId;
    if (!maskBitsValid(&tw.wary_mask, def_count)) return error.BadId;

    var z: usize = 0;
    while (z < def.MAX_ZONES) : (z += 1) {
        var d: i32 = def_count;
        while (d < def.MAX_CREATURES) : (d += 1) {
            const ri: usize = z * def.MAX_CREATURES + @intCast(usize, d);
            if (tw.ready[ri] != 0) return error.BadId;
        }
    }

    i = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        if (tw.field_record.expertise[i] < 0 or tw.field_record.expertise[i] > 5) {
            return error.Damaged;
        }
    }
    i = 0;
    while (i < 5) : (i += 1) {
        if (tw.field_record.boat[i] < 0 or tw.field_record.boat[i] > 3) {
            return error.Damaged;
        }
    }

    w.* = tw;
    exp.* = te;
    return;
}

fn parseFieldRecord(val: []const u8, fr: *def.FieldRecord) bool {
    var vals: [FIELD_RECORD_LEN]i32 = undefined;
    if (!parseI32Array(val, vals[0..])) return false;
    const rec = def.FieldRecord{
        .cycles = vals[0],
        .field_phases = vals[1],
        .creatures_seen = vals[2],
        .rares_seen = vals[3],
        .bosses_killed = vals[4],
        .final_phase2 = vals[5],
        .subdued = vals[6],
        .killed = vals[7],
        .overkilled = vals[8],
        .expertise = [def.MAX_MATERIALS]i32{
            vals[9], vals[10], vals[11], vals[12], vals[13],
            vals[14], vals[15], vals[16], vals[17], vals[18],
        },
        .money_earned = vals[19],
        .cosmetics = vals[20],
        .boat = [5]i32{ vals[21], vals[22], vals[23], vals[24], vals[25] },
        .cosmetics_mask = 0,
    };
    fr.* = rec;
    return true;
}

fn parseLastRun(val: []const u8, lr: *def.LastRun) bool {
    var vals: [LAST_RUN_LEN]i32 = undefined;
    if (!parseI32Array(val, vals[0..])) return false;
    const rec = def.LastRun{
        .cycles = vals[0],
        .phase2 = vals[1],
        .outcome = vals[2],
        .actions = vals[3],
        .hull_spent = vals[4],
        .boss_kills = vals[5],
    };
    lr.* = rec;
    return true;
}
