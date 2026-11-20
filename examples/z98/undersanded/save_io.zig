// save_io.zig — UNDERSANDED save image builder and CRC verifier (spec §32).
//
// Serializes World/Expedition into the canonical format-2 bytes and re-reads a
// temp file to prove its CRC. File lifecycle (temp/bak/rename) lives in the
// persist.zig hub; this module is pure serialization plus one verified read.

const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");
const file_mod = @import("std_file.zig");
const def = @import("def.zig");
const scan = @import("save_scan.zig");
const text_scan = @import("text_scan.zig");

const SaveErr = scan.SaveErr;

var g_verify_arena_buf: [256 * 1024]u8 = undefined;


fn appendInt(out: *buf_mod.Buf, v: i32) void {
    var tmp: [24]u8 = undefined;
    var n: usize = 0;
    text_scan.appendInt(tmp[0..], &n, @intCast(i64, v));
    buf_mod.append(out, tmp[0..n]) catch {};
}

fn appendUint(out: *buf_mod.Buf, v: u32) void {
    var tmp: [24]u8 = undefined;
    var n: usize = 0;
    text_scan.appendUint(tmp[0..], &n, @intCast(u64, v));
    buf_mod.append(out, tmp[0..n]) catch {};
}

fn hexChar(nib: u32) u8 {
    if (nib < 10) return @intCast(u8, @intCast(u32, '0') + nib);
    return @intCast(u8, @intCast(u32, 'a') + nib - 10);
}

fn appendHex8(out: *buf_mod.Buf, v: u32) void {
    buf_mod.append(out, "0x") catch {};
    var shift: i32 = 28;
    while (shift >= 0) : (shift -= 4) {
        const nib: u32 = (v >> @intCast(u32, shift)) & @intCast(u32, 0xF);
        buf_mod.appendByte(out, hexChar(nib)) catch {};
    }
}

fn nl(out: *buf_mod.Buf) void {
    buf_mod.appendByte(out, '\n') catch {};
}

fn wKVInt(out: *buf_mod.Buf, key: []const u8, v: i32) void {
    buf_mod.append(out, key) catch {};
    buf_mod.appendByte(out, '=') catch {};
    appendInt(out, v);
    nl(out);
}

fn wKVUint(out: *buf_mod.Buf, key: []const u8, v: u32) void {
    buf_mod.append(out, key) catch {};
    buf_mod.appendByte(out, '=') catch {};
    appendUint(out, v);
    nl(out);
}

fn wArrI32(out: *buf_mod.Buf, key: []const u8, vals: []const i32) void {
    buf_mod.append(out, key) catch {};
    buf_mod.appendByte(out, '=') catch {};
    var i: usize = 0;
    while (i < vals.len) : (i += 1) {
        if (i != 0) buf_mod.appendByte(out, ',') catch {};
        appendInt(out, vals[i]);
    }
    nl(out);
}

fn wArrU32(out: *buf_mod.Buf, key: []const u8, vals: []const u32) void {
    buf_mod.append(out, key) catch {};
    buf_mod.appendByte(out, '=') catch {};
    var i: usize = 0;
    while (i < vals.len) : (i += 1) {
        if (i != 0) buf_mod.appendByte(out, ',') catch {};
        appendUint(out, vals[i]);
    }
    nl(out);
}

fn wSection(out: *buf_mod.Buf, name: []const u8) void {
    buf_mod.appendByte(out, '[') catch {};
    buf_mod.append(out, name) catch {};
    buf_mod.appendByte(out, ']') catch {};
    nl(out);
}

fn writeWorld(out: *buf_mod.Buf, w: *const def.World) void {
    wSection(out, "world");
    wKVInt(out, "cycle", w.cycle);
    wKVInt(out, "phase", w.phase);
    wArrU32(out, "seen_mask", w.seen_mask[0..]);
    wKVInt(out, "field_phases", w.field_phases);
    wKVInt(out, "hull", w.hull);
    wKVUint(out, "family_overkill_mask", w.family_overkill_mask);
    wArrU32(out, "wary_mask", w.wary_mask[0..]);
    wKVUint(out, "rng_state", w.rng_state);
    wKVInt(out, "money", w.money);
    wArrI32(out, "expertise", w.expertise[0..]);
    wArrI32(out, "materials", w.materials[0..]);
    wKVUint(out, "tools_owned", w.tools_owned);
    wKVInt(out, "tool_selected", w.tool_selected);
    wKVUint(out, "cosmetics_owned", w.cosmetics_owned);
    wKVUint(out, "cosmetics_unlocked", w.cosmetics_unlocked);
}

fn writeBoat(out: *buf_mod.Buf, w: *const def.World) void {
    wSection(out, "boat");
    wArrI32(out, "boat", w.boat[0..]);
}

fn writeCooldowns(out: *buf_mod.Buf, w: *const def.World) void {
    wSection(out, "cooldowns");
    wArrI32(out, "ready", w.ready[0..]);
    wArrI32(out, "release_bonus", w.release_bonus[0..]);
    wArrI32(out, "lockout_until", w.lockout_until[0..]);
}

fn writeJournal(out: *buf_mod.Buf, w: *const def.World) void {
    wSection(out, "journal");
    wArrU32(out, "journal_mask", w.journal_mask[0..]);
    wArrU32(out, "journal_viewed", w.journal_viewed[0..]);
    wKVUint(out, "tooltip_shown", w.tooltip_shown);
}

fn writeExpedition(out: *buf_mod.Buf, e: *const def.Expedition) void {
    wSection(out, "expedition");
    wKVInt(out, "active", e.active);
    wKVInt(out, "zone", e.zone);
    wKVInt(out, "fight_index", e.fight_index);
    wKVUint(out, "seed", e.seed);
    wArrI32(out, "hold", e.hold[0..]);
    wKVInt(out, "hold_n", e.hold_n);
    wKVInt(out, "tool", e.tool);
    wKVInt(out, "tool_charge", e.tool_charge);
    wKVInt(out, "tool_broken", e.tool_broken);
    wKVInt(out, "pending_cond", e.pending_cond);
}

fn writeFieldRecord(out: *buf_mod.Buf, fr: *const def.FieldRecord) void {
    buf_mod.append(out, "field_record=") catch {};
    appendInt(out, fr.cycles);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.field_phases);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.creatures_seen);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.rares_seen);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.bosses_killed);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.final_phase2);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.subdued);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.killed);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.overkilled);
    var i: usize = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        buf_mod.appendByte(out, ',') catch {};
        appendInt(out, fr.expertise[i]);
    }
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.money_earned);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, fr.cosmetics);
    i = 0;
    while (i < 5) : (i += 1) {
        buf_mod.appendByte(out, ',') catch {};
        appendInt(out, fr.boat[i]);
    }
    nl(out);
}

fn writeLastRun(out: *buf_mod.Buf, lr: *const def.LastRun) void {
    buf_mod.append(out, "last_run=") catch {};
    appendInt(out, lr.cycles);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, lr.phase2);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, lr.outcome);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, lr.actions);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, lr.hull_spent);
    buf_mod.appendByte(out, ',') catch {};
    appendInt(out, lr.boss_kills);
    nl(out);
}

fn writeScore(out: *buf_mod.Buf, w: *const def.World) void {
    wSection(out, "score");
    wKVInt(out, "field_record_written", w.field_record_written);
    writeFieldRecord(out, &w.field_record);
    wKVUint(out, "boss_variants_seen", w.boss_variants_seen);
    wKVInt(out, "boss_kills", w.boss_kills);
    writeLastRun(out, &w.last_run);
    wKVInt(out, "score_subdued", w.score_subdued);
    wKVInt(out, "score_killed", w.score_killed);
    wKVInt(out, "score_overkilled", w.score_overkilled);
    wKVInt(out, "score_money_earned", w.score_money_earned);
}


fn contentVersion() i32 {
    if (def.content_override) |t| return t.content_version;
    return 2;
}

pub fn buildSave(out: *buf_mod.Buf, w: *const def.World, exp: *const def.Expedition) SaveErr!void {
    buf_mod.append(out, "version=") catch return SaveErr.Damaged;
    appendInt(out, scan.SAVE_VERSION);
    nl(out);
    buf_mod.append(out, "data_version=") catch return SaveErr.Damaged;
    appendInt(out, contentVersion());
    nl(out);

    writeWorld(out, w);
    writeBoat(out, w);
    writeCooldowns(out, w);
    writeJournal(out, w);
    writeExpedition(out, exp);
    writeScore(out, w);
    wSection(out, "options");

    const prefix = buf_mod.slice(out);
    if (prefix.len + 32 > scan.MAX_FILE) return SaveErr.Damaged;
    const hash = scan.crcOf(prefix);

    wSection(out, "crc32");
    buf_mod.append(out, "hash=") catch return SaveErr.Damaged;
    appendHex8(out, hash);
    nl(out);

    if (buf_mod.slice(out).len > scan.MAX_FILE) return SaveErr.Damaged;
    return;
}

// Step 3: re-read the temp file and prove its CRC before any rename. Mirrors
// saveRead's section-order scan but skips the field/ID checks (a save may carry
// a state that saveRead rejects; the write path only owns file integrity).
pub fn verifyCrcFile(path: []const u8) SaveErr!void {
    var arena = arena_mod.init(g_verify_arena_buf[0..]);
    const content = file_mod.readAll(&arena, path) catch |e| return scan.mapFileError(e);
    if (content.len > scan.MAX_FILE) return error.Damaged;

    var at: usize = 0;
    var line: scan.Line = undefined;
    var section: i32 = -1;
    var next_sec: i32 = 0;
    var saw_hash = false;
    var crc_start: usize = 0;
    var hash: u32 = 0;

    while (scan.nextLine(content, &at, &line)) {
        const t = text_scan.stripCR(content[line.start..line.end]);
        if (t.len == 0) return error.Damaged;
        if (t.len > scan.MAX_LINE) return error.Damaged;
        if (saw_hash) return error.Damaged;

        if (t[0] == '[') {
            var name: []const u8 = "";
            if (!scan.sectionName(t, &name)) return error.Damaged;
            const sid = scan.sectionId(name);
            if (sid < 0) return error.Damaged;
            if (sid != next_sec) return error.Damaged;
            if (sid == scan.SEC_CRC) crc_start = line.start;
            section = sid;
            next_sec = sid + 1;
            continue;
        }

        if (section == scan.SEC_CRC) {
            var key: []const u8 = "";
            var val: []const u8 = "";
            if (!scan.parseScalar(t, &key, &val)) return error.Damaged;
            if (!scan.eql(key, "hash")) return error.Damaged;
            hash = scan.parseHexU32(val) orelse return error.Damaged;
            saw_hash = true;
        }
    }

    if (next_sec != scan.SEC_CRC + 1 or !saw_hash) return error.Damaged;
    if (crc_start > content.len) return error.Damaged;
    if (scan.crcOf(content[0..crc_start]) != hash) return error.BadHash;
}
