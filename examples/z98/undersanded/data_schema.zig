// data_schema.zig — UNDERSANDED data.z98 row schemas and parsers (spec §25.10).
//
// Owns the per-section key sets, required-field helpers, row parsers, text-key
// lookup and rule packing. The loader (data_load.zig) drives these parsers and
// owns file-level orchestration; the dump (data_dump.zig) reuses the key names.

const parse = @import("std_parse");
const def = @import("def.zig");
const text_scan = @import("text_scan.zig");
const scan = @import("data_scan.zig");
const state = @import("data_state.zig");
const fallback = @import("data_fallback.zig");

// One named error set per subsystem (R15). `err_line` is the 1-based line of
// the last DamagedLine/BadRef/Overflow/TooMany failure (0 = none/success).
pub const LoadErr = error{ Missing, DamagedLine, Overflow, BadSentinel, BadRef, TooMany, Io };

pub fn failLine(line: i32) LoadErr {
    state.err_line = line;
    return error.DamagedLine;
}

fn keyIn(keys: []const []const u8, key: []const u8) bool {
    var i: usize = 0;
    while (i < keys.len) : (i += 1) {
        if (scan.eql(keys[i], key)) return true;
    }
    return false;
}

fn findField(fields: []const scan.RowField, n: usize, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (scan.eql(fields[i].key, key)) return fields[i].val;
    }
    return null;
}

fn reqField(fields: []const scan.RowField, n: usize, key: []const u8, line: i32) LoadErr![]const u8 {
    const v = findField(fields, n, key) orelse {
        state.err_line = line;
        return error.DamagedLine;
    };
    return v;
}

fn reqInt(fields: []const scan.RowField, n: usize, key: []const u8, line: i32) LoadErr!i32 {
    const v = try reqField(fields, n, key, line);
    return scan.parseI32(v) orelse {
        state.err_line = line;
        return error.DamagedLine;
    };
}

fn reqUint(fields: []const scan.RowField, n: usize, key: []const u8, line: i32) LoadErr!u32 {
    const v = try reqField(fields, n, key, line);
    return parse.parseUint(v) orelse {
        state.err_line = line;
        return error.DamagedLine;
    };
}

// ---- schemas --------------------------------------------------------------

const CREATURE_KEYS = [73][]const u8{
    "id", "name", "family", "role", "zone_mask", "phase_mask", "hp", "resolve",
    "speed", "attack", "thrash_regen", "despair_regen", "armor_pct", "flags",
    "resist_restrain_pct", "blind_chance", "subdue_chance", "discharge_stat",
    "discharge_th", "discharge_dmg", "armor_below_th", "armor_below_pct",
    "speed_below_stat", "speed_below_th", "speed_below_add", "atk_below_th",
    "atk_below_pct", "flee_kind", "flee_th", "grudge_family", "grudge_kind",
    "grudge_value",
    "sub0_part", "sub0_count", "sub1_part", "sub1_count",
    "sub2_part", "sub2_count", "sub3_part", "sub3_count",
    "sub4_part", "sub4_count", "sub5_part", "sub5_count",
    "kill0_part", "kill0_count", "kill1_part", "kill1_count",
    "kill2_part", "kill2_count", "kill3_part", "kill3_count",
    "kill4_part", "kill4_count", "kill5_part", "kill5_count",
    "over0_part", "over0_count", "over1_part", "over1_count",
    "over2_part", "over2_count", "over3_part", "over3_count",
    "over4_part", "over4_count", "over5_part", "over5_count",
    "sale", "respawn_sub", "respawn_kill", "respawn_over", "counter_tool",
};

pub const SUB_PART = [def.MAX_DROP_LINES][]const u8{ "sub0_part", "sub1_part", "sub2_part", "sub3_part", "sub4_part", "sub5_part" };
pub const SUB_COUNT = [def.MAX_DROP_LINES][]const u8{ "sub0_count", "sub1_count", "sub2_count", "sub3_count", "sub4_count", "sub5_count" };
pub const KILL_PART = [def.MAX_DROP_LINES][]const u8{ "kill0_part", "kill1_part", "kill2_part", "kill3_part", "kill4_part", "kill5_part" };
pub const KILL_COUNT = [def.MAX_DROP_LINES][]const u8{ "kill0_count", "kill1_count", "kill2_count", "kill3_count", "kill4_count", "kill5_count" };
pub const OVER_PART = [def.MAX_DROP_LINES][]const u8{ "over0_part", "over1_part", "over2_part", "over3_part", "over4_part", "over5_part" };
pub const OVER_COUNT = [def.MAX_DROP_LINES][]const u8{ "over0_count", "over1_count", "over2_count", "over3_count", "over4_count", "over5_count" };

const RULE_KEYS = [8][]const u8{
    "owner", "cond_op", "cond_a", "cond_b", "effect_op", "effect_a", "effect_b", "timing",
};

const toolKeys = [8][]const u8{
    "id", "kind", "cost0_kind", "cost0_amt", "cost1_kind", "cost1_amt",
    "cost2_kind", "cost2_amt",
};

pub const COST_KIND = [3][]const u8{ "cost0_kind", "cost1_kind", "cost2_kind" };
pub const COST_AMT = [3][]const u8{ "cost0_amt", "cost1_amt", "cost2_amt" };

const UPGRADE_KEYS = [8][]const u8{
    "axis", "tier", "cost0_kind", "cost0_amt", "cost1_kind", "cost1_amt",
    "cost2_kind", "cost2_amt",
};

const COSMETIC_KEYS = [3][]const u8{ "name", "price", "unlock" };

const ENCOUNTER_KEYS = [4][]const u8{ "zone", "phase", "def_index", "weight" };

const ZONE_KEYS = [3][]const u8{ "id", "cost", "boss" };

fn readDrops(fields: []const scan.RowField, n: usize, parts: []const []const u8, counts: []const []const u8, line: i32, out: *[def.MAX_DROP_LINES]def.DropLine) LoadErr!void {
    var k: usize = 0;
    while (k < def.MAX_DROP_LINES) : (k += 1) {
        const pv = findField(fields, n, parts[k]);
        const cv = findField(fields, n, counts[k]);
        if (pv == null and cv == null) {
            out[k] = def.DropLine{ .part = 0, .count = 0 };
        } else if (pv == null or cv == null) {
            state.err_line = line;
            return error.DamagedLine;
        } else {
            const p = scan.parseI32(pv orelse "") orelse {
                state.err_line = line;
                return error.DamagedLine;
            };
            const c = scan.parseI32(cv orelse "") orelse {
                state.err_line = line;
                return error.DamagedLine;
            };
            out[k] = def.DropLine{ .part = p, .count = c };
        }
    }
}

pub fn parseCreature(fields: []const scan.RowField, n: usize, line: i32, out: *def.CreatureDef) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(CREATURE_KEYS[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }

    var d = fallback.zeroDef();
    d.id = try reqInt(fields, n, "id", line);

    const nm = try reqField(fields, n, "name", line);
    if (nm.len > def.MAX_NAME_LEN) {
        state.err_line = line;
        return error.DamagedLine;
    }
    i = 0;
    while (i < nm.len) : (i += 1) {
        d.name[i] = nm[i];
    }
    d.name_len = @intCast(i32, nm.len);

    d.family = try reqInt(fields, n, "family", line);
    d.role = try reqInt(fields, n, "role", line);
    d.zone_mask = try reqUint(fields, n, "zone_mask", line);
    d.phase_mask = try reqUint(fields, n, "phase_mask", line);
    d.hp = try reqInt(fields, n, "hp", line);
    d.resolve = try reqInt(fields, n, "resolve", line);
    d.speed = try reqInt(fields, n, "speed", line);
    d.attack = try reqInt(fields, n, "attack", line);
    d.thrash_regen = try reqInt(fields, n, "thrash_regen", line);
    d.despair_regen = try reqInt(fields, n, "despair_regen", line);
    d.armor_pct = try reqInt(fields, n, "armor_pct", line);
    d.flags = try reqUint(fields, n, "flags", line);
    d.resist_restrain_pct = try reqInt(fields, n, "resist_restrain_pct", line);
    d.blind_chance = try reqInt(fields, n, "blind_chance", line);
    d.subdue_chance = try reqInt(fields, n, "subdue_chance", line);
    d.discharge_stat = try reqInt(fields, n, "discharge_stat", line);
    d.discharge_th = try reqInt(fields, n, "discharge_th", line);
    d.discharge_dmg = try reqInt(fields, n, "discharge_dmg", line);
    d.armor_below_th = try reqInt(fields, n, "armor_below_th", line);
    d.armor_below_pct = try reqInt(fields, n, "armor_below_pct", line);
    d.speed_below_stat = try reqInt(fields, n, "speed_below_stat", line);
    d.speed_below_th = try reqInt(fields, n, "speed_below_th", line);
    d.speed_below_add = try reqInt(fields, n, "speed_below_add", line);
    d.atk_below_th = try reqInt(fields, n, "atk_below_th", line);
    d.atk_below_pct = try reqInt(fields, n, "atk_below_pct", line);
    d.flee_kind = try reqInt(fields, n, "flee_kind", line);
    d.flee_th = try reqInt(fields, n, "flee_th", line);
    d.grudge_family = try reqInt(fields, n, "grudge_family", line);
    d.grudge_kind = try reqInt(fields, n, "grudge_kind", line);
    d.grudge_value = try reqInt(fields, n, "grudge_value", line);

    try readDrops(fields, n, SUB_PART[0..], SUB_COUNT[0..], line, &d.sub);
    try readDrops(fields, n, KILL_PART[0..], KILL_COUNT[0..], line, &d.kill);
    try readDrops(fields, n, OVER_PART[0..], OVER_COUNT[0..], line, &d.over);

    d.sale = try reqInt(fields, n, "sale", line);
    d.respawn[0] = try reqInt(fields, n, "respawn_sub", line);
    d.respawn[1] = try reqInt(fields, n, "respawn_kill", line);
    d.respawn[2] = try reqInt(fields, n, "respawn_over", line);
    d.counter_tool = try reqInt(fields, n, "counter_tool", line);
    d.rule_start = 0;
    d.rule_count = 0;

    out.* = d;
}

pub fn parseRule(fields: []const scan.RowField, n: usize, line: i32, owner: *i32, out: *def.Rule) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(RULE_KEYS[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }
    owner.* = try reqInt(fields, n, "owner", line);
    var r = fallback.zeroRule();
    r.cond_op = try reqInt(fields, n, "cond_op", line);
    r.cond_a = try reqInt(fields, n, "cond_a", line);
    r.cond_b = try reqInt(fields, n, "cond_b", line);
    r.effect_op = try reqInt(fields, n, "effect_op", line);
    r.effect_a = try reqInt(fields, n, "effect_a", line);
    r.effect_b = try reqInt(fields, n, "effect_b", line);
    r.timing = try reqInt(fields, n, "timing", line);
    out.* = r;
}

pub fn parseTool(fields: []const scan.RowField, n: usize, line: i32, out: *def.ToolRow) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(toolKeys[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }
    var tr = fallback.zeroTool();
    tr.id = try reqInt(fields, n, "id", line);
    tr.kind = try reqInt(fields, n, "kind", line);
    i = 0;
    while (i < 3) : (i += 1) {
        const k = try reqInt(fields, n, COST_KIND[i], line);
        const a = try reqInt(fields, n, COST_AMT[i], line);
        tr.cost[i] = def.CostSlot{ .kind = k, .amt = a };
    }
    out.* = tr;
}

pub fn parseUpgrade(fields: []const scan.RowField, n: usize, line: i32, out: *def.UpgradeRow) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(UPGRADE_KEYS[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }
    var ur = fallback.zeroUpgrade();
    ur.axis = try reqInt(fields, n, "axis", line);
    ur.tier = try reqInt(fields, n, "tier", line);
    i = 0;
    while (i < 3) : (i += 1) {
        const k = try reqInt(fields, n, COST_KIND[i], line);
        const a = try reqInt(fields, n, COST_AMT[i], line);
        ur.cost[i] = def.CostSlot{ .kind = k, .amt = a };
    }
    out.* = ur;
}

pub fn parseCosmetic(fields: []const scan.RowField, n: usize, line: i32, out: *def.CosmeticRow) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(COSMETIC_KEYS[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }
    const nm = try reqField(fields, n, "name", line);
    const price = try reqInt(fields, n, "price", line);
    const unlock = try reqInt(fields, n, "unlock", line);
    out.* = def.CosmeticRow{ .name = nm, .price = price, .unlock = unlock };
}

pub fn parseEncounter(fields: []const scan.RowField, n: usize, line: i32, t: *def.Tables) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(ENCOUNTER_KEYS[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }
    const zone = try reqInt(fields, n, "zone", line);
    const phase = try reqInt(fields, n, "phase", line);
    const def_index = try reqInt(fields, n, "def_index", line);
    const weight = try reqInt(fields, n, "weight", line);
    if (zone < 0 or zone >= @intCast(i32, def.MAX_ZONES) or phase < 0 or phase > 1) {
        state.err_line = line;
        return error.BadRef;
    }
    const ci: usize = @intCast(usize, zone) * 2 + @intCast(usize, phase);
    const base: usize = @intCast(usize, zone) * 2 * def.MAX_ENCOUNTER +
        @intCast(usize, phase) * def.MAX_ENCOUNTER;
    const count = @intCast(usize, t.enc_count[ci]);
    if (count >= def.MAX_ENCOUNTER) {
        state.err_line = line;
        return error.Overflow;
    }
    t.encounters[base + count] = def.EncounterRow{ .def_index = def_index, .weight = weight };
    state.enc_src[base + count] = line;
    t.enc_count[ci] = @intCast(i32, count + 1);
}

pub fn parseZone(fields: []const scan.RowField, n: usize, line: i32, t: *def.Tables) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(ZONE_KEYS[0..], fields[i].key)) {
            state.err_line = line;
            return error.DamagedLine;
        }
    }
    const id = try reqInt(fields, n, "id", line);
    const cost = try reqInt(fields, n, "cost", line);
    const boss = try reqInt(fields, n, "boss", line);
    if (id < 0 or id >= @intCast(i32, def.MAX_ZONES)) {
        state.err_line = line;
        return error.BadRef;
    }
    t.zone_cost[@intCast(usize, id)] = cost;
    t.zone_boss[@intCast(usize, id)] = boss;
    state.zone_src[@intCast(usize, id)] = line;
}

pub fn textKeyKnown(k: []const u8) bool {
    if (k.len > 7 and scan.eql(k[0..7], "manual.")) {
        const n = scan.parseI32(k[7..]) orelse return false;
        return n >= 1 and n <= 8;
    }
    if (k.len > 8 and scan.eql(k[0..8], "journal.")) {
        const n = scan.parseI32(k[8..]) orelse return false;
        return n >= 1 and n <= 19;
    }
    if (k.len > 7 and scan.eql(k[0..7], "legend.")) {
        const n = scan.parseI32(k[7..]) orelse return false;
        return n >= 1 and n <= 2;
    }
    if (k.len > 5 and scan.eql(k[0..5], "zone.")) {
        const n = scan.parseI32(k[5..]) orelse return false;
        return n >= 1 and n <= 9;
    }
    if (k.len > 6 and scan.eql(k[0..6], "error.")) {
        const n = scan.parseI32(k[6..]) orelse return false;
        return n >= 1 and n <= 6;
    }
    return false;
}

// Text lookup against the installed content override. Returns null when no
// content has been installed (the compiled-in fallback ships no [text]).
pub fn textFind(key: []const u8) ?[]const u8 {
    const t = def.content_override orelse return null;
    return textFindIn(t, key);
}

pub fn textFindIn(t: *const def.Tables, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < @intCast(usize, t.text_count)) : (i += 1) {
        if (scan.eql(t.text_key[i], key)) return t.text_val[i];
    }
    return null;
}

pub fn packRules(t: *def.Tables, owners: *const [def.MAX_RULES]i32, rows: *const [def.MAX_RULES]def.Rule, lines: *const [def.MAX_RULES]i32, n: usize) LoadErr!void {
    var emitted: [def.MAX_RULES]bool = undefined;
    var i: usize = 0;
    while (i < def.MAX_RULES) : (i += 1) {
        emitted[i] = false;
    }

    var out_i: usize = 0;
    i = 0;
    while (i < n) : (i += 1) {
        if (emitted[i]) continue;
        const owner = owners[i];

        var di: i32 = -1;
        var d: usize = 0;
        while (d < @intCast(usize, t.def_count)) : (d += 1) {
            if (t.defs[d].id == owner) {
                di = @intCast(i32, d);
                break;
            }
        }
        if (di < 0) {
            state.err_line = lines[i];
            return error.BadRef;
        }

        const start = out_i;
        var j: usize = i;
        while (j < n) : (j += 1) {
            if (emitted[j]) continue;
            if (owners[j] != owner) continue;
            if (out_i >= def.MAX_RULES) {
                state.err_line = lines[j];
                return error.Overflow;
            }
            t.rules[out_i] = rows[j];
            state.rule_src[out_i] = lines[j];
            out_i += 1;
            emitted[j] = true;
        }

        var cd = t.defs[@intCast(usize, di)];
        cd.rule_start = @intCast(i32, start);
        cd.rule_count = @intCast(i32, out_i - start);
        t.defs[@intCast(usize, di)] = cd;
    }
    t.rule_count = @intCast(i32, out_i);
}
