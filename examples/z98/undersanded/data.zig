// data.zig — UNDERSANDED M6 data.z98 scanner + loader (spec §25.10).
//
// Task 2 supplied the pure scanner primitives below. Task 3 adds whole-file
// reading, section/row schema enforcement, rules packing, the compiled-in
// fallback builder, the static override installers, and the field-by-field
// dump. All file bytes and [text] slices live in the caller's permanent arena.

const parse = @import("std_parse");
const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const buf_mod = @import("std_buf.zig");
const def = @import("def.zig");
const creatures = @import("creatures_t1.zig");
const tables_t1 = @import("tables_t1.zig");

// §25.10 row-line cap (bytes, \r excluded).
pub const MAX_LINE: usize = 4096;

// Broadest authored row is [creatures] at 73 keys (MAX_DROP_LINES=6); 80
// leaves headroom.
pub const ROW_MAX: usize = 80;

pub const RowField = struct { key: []const u8, val: []const u8 };

pub fn parseI32(s: []const u8) ?i32 {
    return parse.parseInt(s);
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn stripCR(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

fn trimSpaces(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

pub fn sectionId(name: []const u8) i32 {
    if (eql(name, "creatures")) return 0;
    if (eql(name, "rules")) return 1;
    if (eql(name, "tools")) return 2;
    if (eql(name, "upgrades")) return 3;
    if (eql(name, "cosmetics")) return 4;
    if (eql(name, "encounter")) return 5;
    if (eql(name, "zones")) return 6;
    if (eql(name, "text")) return 7;
    return -1;
}

// 0 blank/comment, 1 header, 2 section, 3 row, 4 error. Stateless: unknown
// section names and unknown row keys are later loader/validator concerns.
pub fn classifyLine(line: []const u8) i32 {
    const s = stripCR(line);
    if (s.len > MAX_LINE) return 4;

    const t = trimSpaces(s);
    if (t.len == 0) return 0;
    if (t[0] == '#') return 0;

    if (eql(t, "format=2")) return 1;
    if (t.len >= 7 and eql(t[0..7], "format=")) return 4;

    if (t[0] == '[') {
        var i: usize = 1;
        while (i < t.len) : (i += 1) {
            if (t[i] == ']') {
                if (i == t.len - 1 and i > 1) return 2;
                return 4;
            }
        }
        return 4;
    }

    var i: usize = 0;
    while (i < t.len) : (i += 1) {
        if (t[i] == '=') return 3;
    }
    return 4;
}

// Comma-separated key=value fields, surrounding spaces trimmed, inner spaces
// kept. Rejects missing '=', empty key/value, duplicate key, and > ROW_MAX
// fields. All-or-nothing: out and n are written only on success.
pub fn parseRowKV(line: []const u8, out: *[ROW_MAX]RowField, n: *usize) bool {
    const s = stripCR(line);
    if (s.len > MAX_LINE) return false;

    var tmp: [ROW_MAX]RowField = undefined;
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;

    while (i <= s.len) : (i += 1) {
        if (i != s.len and s[i] != ',') continue;

        const field = trimSpaces(s[start..i]);
        var eq: usize = 0;
        var found: bool = false;
        while (eq < field.len and !found) : (eq += 1) {
            if (field[eq] == '=') found = true;
        }
        if (!found) return false;

        const key = trimSpaces(field[0..eq - 1]);
        const val = trimSpaces(field[eq..]);
        if (key.len == 0 or val.len == 0) return false;

        var k: usize = 0;
        while (k < count) : (k += 1) {
            if (eql(tmp[k].key, key)) return false;
        }

        if (count >= ROW_MAX) return false;
        tmp[count] = RowField{ .key = key, .val = val };
        count += 1;
        start = i + 1;
    }

    var j: usize = 0;
    while (j < count) : (j += 1) {
        out[j] = tmp[j];
    }
    n.* = count;
    return true;
}

// ---- §25.10 loader --------------------------------------------------------

// One named error set per subsystem (R15). `err_line` is the 1-based line of
// the last DamagedLine/BadRef/Overflow/TooMany failure (0 = none/success).
pub const LoadErr = error{ Missing, DamagedLine, Overflow, BadSentinel, BadRef, TooMany, Io };

pub var err_line: i32 = 0;

// BSS Tables image owned by the data layer; the game/startup loads into this
// and installs it (§35).
pub var g_tables: def.Tables = undefined;

// Source line probes for validate.zig. Populated by loadFile; read only when
// lines_ready is true (fixtures), so fallback/synthetic images report line 0.
pub var lines_ready: bool = false;
pub var header_line: i32 = 0;
pub var last_line: i32 = 0;
pub var section_line: [8]i32 = undefined;
pub var def_src: [def.MAX_CREATURES]i32 = undefined;
pub var rule_src: [def.MAX_RULES]i32 = undefined;
pub var tool_src: [def.MAX_TOOLS]i32 = undefined;
pub var upgrade_src: [15]i32 = undefined;
pub var cosmetic_src: [def.MAX_COSMETICS]i32 = undefined;
pub var enc_src: [def.MAX_ZONES * 2 * def.MAX_ENCOUNTER]i32 = undefined;
pub var zone_src: [def.MAX_ZONES]i32 = undefined;

pub fn resetLines() void {
    lines_ready = false;
    header_line = 0;
    last_line = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        section_line[i] = 0;
    }
    i = 0;
    while (i < def.MAX_CREATURES) : (i += 1) {
        def_src[i] = 0;
    }
    i = 0;
    while (i < def.MAX_RULES) : (i += 1) {
        rule_src[i] = 0;
    }
    i = 0;
    while (i < def.MAX_TOOLS) : (i += 1) {
        tool_src[i] = 0;
    }
    i = 0;
    while (i < 15) : (i += 1) {
        upgrade_src[i] = 0;
    }
    i = 0;
    while (i < def.MAX_COSMETICS) : (i += 1) {
        cosmetic_src[i] = 0;
    }
    i = 0;
    while (i < def.MAX_ZONES * 2 * def.MAX_ENCOUNTER) : (i += 1) {
        enc_src[i] = 0;
    }
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        zone_src[i] = 0;
    }
}

fn srcAt(i: i32, n: i32, arr: []const i32) i32 {
    if (!lines_ready) return 0;
    if (i < 0 or i >= n) return 0;
    return arr[@intCast(usize, i)];
}

pub fn headerSrcLine() i32 {
    if (!lines_ready) return 0;
    return header_line;
}

pub fn lastSrcLine() i32 {
    if (!lines_ready) return 0;
    return last_line;
}

pub fn sectionSrcLine(sid: i32) i32 {
    if (!lines_ready) return 0;
    if (sid < 0 or sid >= 8) return 0;
    return section_line[@intCast(usize, sid)];
}

pub fn defSrcLine(i: i32) i32 {
    return srcAt(i, @intCast(i32, def.MAX_CREATURES), def_src[0..]);
}

pub fn ruleSrcLine(i: i32) i32 {
    return srcAt(i, @intCast(i32, def.MAX_RULES), rule_src[0..]);
}

pub fn toolSrcLine(i: i32) i32 {
    return srcAt(i, @intCast(i32, def.MAX_TOOLS), tool_src[0..]);
}

pub fn upgradeSrcLine(i: i32) i32 {
    return srcAt(i, 15, upgrade_src[0..]);
}

pub fn cosmeticSrcLine(i: i32) i32 {
    return srcAt(i, @intCast(i32, def.MAX_COSMETICS), cosmetic_src[0..]);
}

pub fn encSrcLine(i: i32) i32 {
    return srcAt(i, @intCast(i32, def.MAX_ZONES * 2 * def.MAX_ENCOUNTER), enc_src[0..]);
}

pub fn zoneSrcLine(i: i32) i32 {
    return srcAt(i, @intCast(i32, def.MAX_ZONES), zone_src[0..]);
}

pub fn install(t: *def.Tables) void {
    def.content_override = t;
}

pub fn uninstall() void {
    def.content_override = null;
}

fn failLine(line: i32) LoadErr {
    err_line = line;
    return error.DamagedLine;
}

fn keyIn(keys: []const []const u8, key: []const u8) bool {
    var i: usize = 0;
    while (i < keys.len) : (i += 1) {
        if (eql(keys[i], key)) return true;
    }
    return false;
}

fn findField(fields: []const RowField, n: usize, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (eql(fields[i].key, key)) return fields[i].val;
    }
    return null;
}

fn reqField(fields: []const RowField, n: usize, key: []const u8, line: i32) LoadErr![]const u8 {
    const v = findField(fields, n, key) orelse {
        err_line = line;
        return error.DamagedLine;
    };
    return v;
}

fn reqInt(fields: []const RowField, n: usize, key: []const u8, line: i32) LoadErr!i32 {
    const v = try reqField(fields, n, key, line);
    return parseI32(v) orelse {
        err_line = line;
        return error.DamagedLine;
    };
}

fn reqUint(fields: []const RowField, n: usize, key: []const u8, line: i32) LoadErr!u32 {
    const v = try reqField(fields, n, key, line);
    return parse.parseUint(v) orelse {
        err_line = line;
        return error.DamagedLine;
    };
}

const ZERO_NAME = [def.MAX_NAME_LEN]u8{
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
};

fn zeroDef() def.CreatureDef {
    return def.CreatureDef{
        .id = 0,
        .name = ZERO_NAME,
        .name_len = 0,
        .family = 0,
        .role = 0,
        .zone_mask = 0,
        .phase_mask = 0,
        .hp = 0,
        .resolve = 0,
        .speed = 0,
        .attack = 0,
        .thrash_regen = 0,
        .despair_regen = 0,
        .armor_pct = 100,
        .flags = 0,
        .resist_restrain_pct = 100,
        .blind_chance = 0,
        .subdue_chance = 95,
        .discharge_stat = 0,
        .discharge_th = 0,
        .discharge_dmg = 0,
        .armor_below_th = 0,
        .armor_below_pct = 0,
        .speed_below_stat = 0,
        .speed_below_th = 0,
        .speed_below_add = 0,
        .atk_below_th = 0,
        .atk_below_pct = 0,
        .flee_kind = 0,
        .flee_th = 0,
        .grudge_family = 0,
        .grudge_kind = 0,
        .grudge_value = 0,
        .sub = [def.MAX_DROP_LINES]def.DropLine{
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
        },
        .kill = [def.MAX_DROP_LINES]def.DropLine{
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
        },
        .over = [def.MAX_DROP_LINES]def.DropLine{
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
            def.DropLine{ .part = 0, .count = 0 },
        },
        .sale = 0,
        .respawn = [3]i32{ 0, 0, 0 },
        .counter_tool = 0,
        .rule_start = 0,
        .rule_count = 0,
    };
}

fn zeroRule() def.Rule {
    return def.Rule{
        .cond_op = 0,
        .cond_a = 0,
        .cond_b = 0,
        .effect_op = 0,
        .effect_a = 0,
        .effect_b = 0,
        .timing = 0,
    };
}

fn zeroCost() def.CostSlot {
    return def.CostSlot{ .kind = 0, .amt = 0 };
}

fn zeroTool() def.ToolRow {
    return def.ToolRow{
        .id = 0,
        .kind = 0,
        .cost = [3]def.CostSlot{ zeroCost(), zeroCost(), zeroCost() },
    };
}

fn zeroUpgrade() def.UpgradeRow {
    return def.UpgradeRow{
        .axis = 0,
        .tier = 0,
        .cost = [3]def.CostSlot{ zeroCost(), zeroCost(), zeroCost() },
    };
}

fn zeroEncounter() def.EncounterRow {
    return def.EncounterRow{ .def_index = 0, .weight = 0 };
}

fn clearTables(t: *def.Tables) void {
    t.def_count = 0;
    t.rule_count = 0;
    t.tool_count = 0;
    t.upgrade_count = 0;
    t.cosmetic_count = 0;
    t.text_count = 0;
    t.content_version = 0;
    t.loaded = 0;

    var i: usize = 0;
    while (i < def.MAX_CREATURES) : (i += 1) {
        t.defs[i] = zeroDef();
    }
    i = 0;
    while (i < def.MAX_RULES) : (i += 1) {
        t.rules[i] = zeroRule();
    }
    i = 0;
    while (i < def.MAX_TOOLS) : (i += 1) {
        t.tools[i] = zeroTool();
    }
    i = 0;
    while (i < 15) : (i += 1) {
        t.upgrades[i] = zeroUpgrade();
    }
    i = 0;
    while (i < def.MAX_COSMETICS) : (i += 1) {
        t.cosmetics[i] = def.CosmeticRow{ .name = "", .price = 0, .unlock = 0 };
    }
    i = 0;
    while (i < def.MAX_ZONES * 2 * def.MAX_ENCOUNTER) : (i += 1) {
        t.encounters[i] = zeroEncounter();
    }
    i = 0;
    while (i < def.MAX_ZONES * 2) : (i += 1) {
        t.enc_count[i] = 0;
    }
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        t.zone_cost[i] = 0;
        t.zone_boss[i] = 0;
    }
    i = 0;
    while (i < def.MAX_TEXT_KEYS) : (i += 1) {
        t.text_key[i] = "";
        t.text_val[i] = "";
    }
}

// Compiled-in T1 fallback in a Tables image. Used by tests, the M6 tier, and
// the tool paths that must run without data.z98 beside the exe.
pub fn buildFallback(out: *def.Tables) void {
    clearTables(out);
    out.content_version = 2;
    out.loaded = 0;

    var i: usize = 0;
    while (i < creatures.DEFS.len) : (i += 1) {
        out.defs[i] = creatures.DEFS[i];
    }
    out.def_count = @intCast(i32, creatures.DEFS.len);

    i = 0;
    while (i < creatures.RULES.len) : (i += 1) {
        out.rules[i] = creatures.RULES[i];
    }
    out.rule_count = @intCast(i32, creatures.RULES.len);

    i = 0;
    while (i < tables_t1.TOOLS.len) : (i += 1) {
        out.tools[i] = tables_t1.TOOLS[i];
    }
    out.tool_count = @intCast(i32, tables_t1.TOOLS.len);

    i = 0;
    while (i < tables_t1.UPGRADES.len) : (i += 1) {
        out.upgrades[i] = tables_t1.UPGRADES[i];
    }
    out.upgrade_count = @intCast(i32, tables_t1.UPGRADES.len);

    i = 0;
    while (i < tables_t1.COSMETICS.len) : (i += 1) {
        out.cosmetics[i] = tables_t1.COSMETICS[i];
    }
    out.cosmetic_count = @intCast(i32, tables_t1.COSMETICS.len);

    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        out.zone_cost[i] = tables_t1.ZONE_COST[i];
        out.zone_boss[i] = tables_t1.ZONE_IS_BOSS[i];
    }

    var z: i32 = 0;
    while (z < @intCast(i32, def.MAX_ZONES)) : (z += 1) {
        var ph: i32 = 0;
        while (ph < 2) : (ph += 1) {
            const r = tables_t1.fallbackRows(z, ph);
            const ci: usize = @intCast(usize, z) * 2 + @intCast(usize, ph);
            const base: usize = @intCast(usize, z) * 2 * def.MAX_ENCOUNTER +
                @intCast(usize, ph) * def.MAX_ENCOUNTER;
            var j: usize = 0;
            while (j < r.len) : (j += 1) {
                out.encounters[base + j] = r[j];
            }
            out.enc_count[ci] = @intCast(i32, r.len);
        }
    }
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

const SUB_PART = [def.MAX_DROP_LINES][]const u8{ "sub0_part", "sub1_part", "sub2_part", "sub3_part", "sub4_part", "sub5_part" };
const SUB_COUNT = [def.MAX_DROP_LINES][]const u8{ "sub0_count", "sub1_count", "sub2_count", "sub3_count", "sub4_count", "sub5_count" };
const KILL_PART = [def.MAX_DROP_LINES][]const u8{ "kill0_part", "kill1_part", "kill2_part", "kill3_part", "kill4_part", "kill5_part" };
const KILL_COUNT = [def.MAX_DROP_LINES][]const u8{ "kill0_count", "kill1_count", "kill2_count", "kill3_count", "kill4_count", "kill5_count" };
const OVER_PART = [def.MAX_DROP_LINES][]const u8{ "over0_part", "over1_part", "over2_part", "over3_part", "over4_part", "over5_part" };
const OVER_COUNT = [def.MAX_DROP_LINES][]const u8{ "over0_count", "over1_count", "over2_count", "over3_count", "over4_count", "over5_count" };

const RULE_KEYS = [8][]const u8{
    "owner", "cond_op", "cond_a", "cond_b", "effect_op", "effect_a", "effect_b", "timing",
};

const TOOL_KEYS = [8][]const u8{
    "id", "kind", "cost0_kind", "cost0_amt", "cost1_kind", "cost1_amt",
    "cost2_kind", "cost2_amt",
};

const COST_KIND = [3][]const u8{ "cost0_kind", "cost1_kind", "cost2_kind" };
const COST_AMT = [3][]const u8{ "cost0_amt", "cost1_amt", "cost2_amt" };

const UPGRADE_KEYS = [8][]const u8{
    "axis", "tier", "cost0_kind", "cost0_amt", "cost1_kind", "cost1_amt",
    "cost2_kind", "cost2_amt",
};

const COSMETIC_KEYS = [3][]const u8{ "name", "price", "unlock" };

const ENCOUNTER_KEYS = [4][]const u8{ "zone", "phase", "def_index", "weight" };

const ZONE_KEYS = [3][]const u8{ "id", "cost", "boss" };

fn readDrops(fields: []const RowField, n: usize, parts: []const []const u8, counts: []const []const u8, line: i32, out: *[def.MAX_DROP_LINES]def.DropLine) LoadErr!void {
    var k: usize = 0;
    while (k < def.MAX_DROP_LINES) : (k += 1) {
        const pv = findField(fields, n, parts[k]);
        const cv = findField(fields, n, counts[k]);
        if (pv == null and cv == null) {
            out[k] = def.DropLine{ .part = 0, .count = 0 };
        } else if (pv == null or cv == null) {
            err_line = line;
            return error.DamagedLine;
        } else {
            const p = parseI32(pv orelse "") orelse {
                err_line = line;
                return error.DamagedLine;
            };
            const c = parseI32(cv orelse "") orelse {
                err_line = line;
                return error.DamagedLine;
            };
            out[k] = def.DropLine{ .part = p, .count = c };
        }
    }
}

fn parseCreature(fields: []const RowField, n: usize, line: i32, out: *def.CreatureDef) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(CREATURE_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }

    var d = zeroDef();
    d.id = try reqInt(fields, n, "id", line);

    const nm = try reqField(fields, n, "name", line);
    if (nm.len > def.MAX_NAME_LEN) {
        err_line = line;
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

fn parseRule(fields: []const RowField, n: usize, line: i32, owner: *i32, out: *def.Rule) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(RULE_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }
    owner.* = try reqInt(fields, n, "owner", line);
    var r = zeroRule();
    r.cond_op = try reqInt(fields, n, "cond_op", line);
    r.cond_a = try reqInt(fields, n, "cond_a", line);
    r.cond_b = try reqInt(fields, n, "cond_b", line);
    r.effect_op = try reqInt(fields, n, "effect_op", line);
    r.effect_a = try reqInt(fields, n, "effect_a", line);
    r.effect_b = try reqInt(fields, n, "effect_b", line);
    r.timing = try reqInt(fields, n, "timing", line);
    out.* = r;
}

fn parseTool(fields: []const RowField, n: usize, line: i32, out: *def.ToolRow) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(TOOL_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }
    var tr = zeroTool();
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

fn parseUpgrade(fields: []const RowField, n: usize, line: i32, out: *def.UpgradeRow) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(UPGRADE_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }
    var ur = zeroUpgrade();
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

fn parseCosmetic(fields: []const RowField, n: usize, line: i32, out: *def.CosmeticRow) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(COSMETIC_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }
    const nm = try reqField(fields, n, "name", line);
    const price = try reqInt(fields, n, "price", line);
    const unlock = try reqInt(fields, n, "unlock", line);
    out.* = def.CosmeticRow{ .name = nm, .price = price, .unlock = unlock };
}

fn parseEncounter(fields: []const RowField, n: usize, line: i32, t: *def.Tables) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(ENCOUNTER_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }
    const zone = try reqInt(fields, n, "zone", line);
    const phase = try reqInt(fields, n, "phase", line);
    const def_index = try reqInt(fields, n, "def_index", line);
    const weight = try reqInt(fields, n, "weight", line);
    if (zone < 0 or zone >= @intCast(i32, def.MAX_ZONES) or phase < 0 or phase > 1) {
        err_line = line;
        return error.BadRef;
    }
    const ci: usize = @intCast(usize, zone) * 2 + @intCast(usize, phase);
    const base: usize = @intCast(usize, zone) * 2 * def.MAX_ENCOUNTER +
        @intCast(usize, phase) * def.MAX_ENCOUNTER;
    const count = @intCast(usize, t.enc_count[ci]);
    if (count >= def.MAX_ENCOUNTER) {
        err_line = line;
        return error.Overflow;
    }
    t.encounters[base + count] = def.EncounterRow{ .def_index = def_index, .weight = weight };
    enc_src[base + count] = line;
    t.enc_count[ci] = @intCast(i32, count + 1);
}

fn parseZone(fields: []const RowField, n: usize, line: i32, t: *def.Tables) LoadErr!void {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!keyIn(ZONE_KEYS[0..], fields[i].key)) {
            err_line = line;
            return error.DamagedLine;
        }
    }
    const id = try reqInt(fields, n, "id", line);
    const cost = try reqInt(fields, n, "cost", line);
    const boss = try reqInt(fields, n, "boss", line);
    if (id < 0 or id >= @intCast(i32, def.MAX_ZONES)) {
        err_line = line;
        return error.BadRef;
    }
    t.zone_cost[@intCast(usize, id)] = cost;
    t.zone_boss[@intCast(usize, id)] = boss;
    zone_src[@intCast(usize, id)] = line;
}

pub fn textKeyKnown(k: []const u8) bool {
    if (k.len > 7 and eql(k[0..7], "manual.")) {
        const n = parseI32(k[7..]) orelse return false;
        return n >= 1 and n <= 8;
    }
    if (k.len > 8 and eql(k[0..8], "journal.")) {
        const n = parseI32(k[8..]) orelse return false;
        return n >= 1 and n <= 19;
    }
    if (k.len > 7 and eql(k[0..7], "legend.")) {
        const n = parseI32(k[7..]) orelse return false;
        return n >= 1 and n <= 2;
    }
    if (k.len > 6 and eql(k[0..6], "error.")) {
        const n = parseI32(k[6..]) orelse return false;
        return n >= 1 and n <= 6;
    }
    return false;
}

fn equalsIndex(line: []const u8) i32 {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] == '=') return @intCast(i32, i);
    }
    return -1;
}

fn finishTextValue(content: []u8, t: *def.Tables, val_start: usize, val_end: usize) void {
    const idx: usize = @intCast(usize, t.text_count);
    var read: usize = val_start;
    var write: usize = val_start;
    var after_nl: bool = false;
    while (read < val_end) : (read += 1) {
        const ch = content[read];
        if (ch == '\r') continue;
        if (after_nl and ch == ' ') {
            after_nl = false;
            continue;
        }
        after_nl = (ch == '\n');
        content[write] = ch;
        write += 1;
    }
    t.text_val[idx] = content[val_start..write];
    t.text_count = @intCast(i32, idx + 1);
}

fn beginTextEntry(content: []u8, t: *def.Tables, line: []const u8, pos: usize, eq: usize, line_no: i32, active: *bool, val_start: *usize, val_end: *usize) LoadErr!void {
    if (active.*) {
        finishTextValue(content, t, val_start.*, val_end.*);
        active.* = false;
    }
    const key = trimSpaces(line[0..eq]);
    if (key.len == 0 or !textKeyKnown(key)) return failLine(line_no);
    const tcount: usize = @intCast(usize, t.text_count);
    var ki: usize = 0;
    while (ki < tcount) : (ki += 1) {
        if (eql(t.text_key[ki], key)) return failLine(line_no);
    }
    if (tcount >= def.MAX_TEXT_KEYS) {
        err_line = line_no;
        return error.TooMany;
    }
    t.text_key[tcount] = key;
    val_start.* = pos + eq + 1;
    val_end.* = pos + line.len;
    active.* = true;
}

fn packRules(t: *def.Tables, owners: *const [def.MAX_RULES]i32, rows: *const [def.MAX_RULES]def.Rule, lines: *const [def.MAX_RULES]i32, n: usize) LoadErr!void {
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
            err_line = lines[i];
            return error.BadRef;
        }

        const start = out_i;
        var j: usize = i;
        while (j < n) : (j += 1) {
            if (emitted[j]) continue;
            if (owners[j] != owner) continue;
            if (out_i >= def.MAX_RULES) {
                err_line = lines[j];
                return error.Overflow;
            }
            t.rules[out_i] = rows[j];
            rule_src[out_i] = lines[j];
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

pub fn loadFile(arena: *arena_mod.Arena, path: []const u8, tables: *def.Tables) LoadErr!void {
    tables.loaded = 0;
    err_line = 0;
    resetLines();
    const content = file_mod.readAll(arena, path) catch return error.Io;

    var tmp: def.Tables = undefined;
    clearTables(&tmp);

    var fields: [ROW_MAX]RowField = undefined;
    var fn_count: usize = 0;
    var header_ok: bool = false;
    var section: i32 = -1;
    var text_section_line: i32 = 0;

    var text_active: bool = false;
    var text_val_start: usize = 0;
    var text_val_end: usize = 0;

    var rule_owner: [def.MAX_RULES]i32 = undefined;
    var rule_row: [def.MAX_RULES]def.Rule = undefined;
    var rule_in_line: [def.MAX_RULES]i32 = undefined;
    var rule_n: usize = 0;
    var tool_n: usize = 0;
    var upgrade_n: usize = 0;
    var cosmetic_n: usize = 0;

    var line_no: i32 = 0;
    var pos: usize = 0;
    while (pos < content.len) {
        var eol = pos;
        while (eol < content.len and content[eol] != '\n') : (eol += 1) {}
        var line = content[pos..eol];
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        line_no += 1;

        const t = trimSpaces(line);

        if (!header_ok) {
            if (t.len == 0 or t[0] == '#') {
                pos = if (eol < content.len) eol + 1 else content.len;
                continue;
            }
            if (eql(line, "format=2")) {
                header_ok = true;
                tmp.content_version = 2;
                header_line = line_no;
            } else {
                return failLine(line_no);
            }
            pos = if (eol < content.len) eol + 1 else content.len;
            continue;
        }

        // Inside a [text] entry the global comment/blank rules do not apply.
        // The entry ends only at the next key= line or [section]. A one-space
        // continuation line is a retained blank paragraph break.
        if (section == 7 and text_active) {
            if (line.len > 0 and line[0] == ' ') {
                text_val_end = pos + line.len;
                pos = if (eol < content.len) eol + 1 else content.len;
                continue;
            }
            if (t.len == 0) return failLine(line_no);
            if (t[0] != '[') {
                const ei = equalsIndex(line);
                if (ei < 0) return failLine(line_no);
                try beginTextEntry(content, &tmp, line, pos, @intCast(usize, ei), line_no, &text_active, &text_val_start, &text_val_end);
                pos = if (eol < content.len) eol + 1 else content.len;
                continue;
            }
            finishTextValue(content, &tmp, text_val_start, text_val_end);
            text_active = false;
        }

        if (t.len == 0 or t[0] == '#') {
            pos = if (eol < content.len) eol + 1 else content.len;
            continue;
        }

        if (section == 7) {
            if (line[0] == ' ') {
                if (line.len > 1 and line[1] == ' ') return failLine(line_no);
                return failLine(line_no);
            }
            if (t[0] != '[') {
                const ei = equalsIndex(line);
                if (ei < 0) return failLine(line_no);
                try beginTextEntry(content, &tmp, line, pos, @intCast(usize, ei), line_no, &text_active, &text_val_start, &text_val_end);
                pos = if (eol < content.len) eol + 1 else content.len;
                continue;
            }
        }

        const cls = classifyLine(line);
        if (cls == 1) {
            return failLine(line_no);
        } else if (cls == 2) {
            if (text_active) {
                finishTextValue(content, &tmp, text_val_start, text_val_end);
                text_active = false;
            }
            const name = t[1 .. t.len - 1];
            const sid = sectionId(name);
            if (sid < 0) return failLine(line_no);
            section = sid;
            section_line[@intCast(usize, sid)] = line_no;
            if (sid == 7) text_section_line = line_no;
        } else if (cls == 3) {
            if (section < 0 or section == 7) return failLine(line_no);
            if (!parseRowKV(line, &fields, &fn_count)) return failLine(line_no);

            if (section == 0) {
                if (@intCast(usize, tmp.def_count) >= def.MAX_CREATURES) {
                    err_line = line_no;
                    return error.Overflow;
                }
                var d = zeroDef();
                try parseCreature(fields[0..], fn_count, line_no, &d);
                tmp.defs[@intCast(usize, tmp.def_count)] = d;
                def_src[@intCast(usize, tmp.def_count)] = line_no;
                tmp.def_count += 1;
            } else if (section == 1) {
                if (rule_n >= def.MAX_RULES) {
                    err_line = line_no;
                    return error.Overflow;
                }
                try parseRule(fields[0..], fn_count, line_no, &rule_owner[rule_n], &rule_row[rule_n]);
                rule_in_line[rule_n] = line_no;
                rule_n += 1;
            } else if (section == 2) {
                if (tool_n >= def.MAX_TOOLS) {
                    err_line = line_no;
                    return error.Overflow;
                }
                var tr = zeroTool();
                try parseTool(fields[0..], fn_count, line_no, &tr);
                tmp.tools[tool_n] = tr;
                tool_src[tool_n] = line_no;
                tool_n += 1;
            } else if (section == 3) {
                if (upgrade_n >= 15) {
                    err_line = line_no;
                    return error.Overflow;
                }
                var ur = zeroUpgrade();
                try parseUpgrade(fields[0..], fn_count, line_no, &ur);
                tmp.upgrades[upgrade_n] = ur;
                upgrade_src[upgrade_n] = line_no;
                upgrade_n += 1;
            } else if (section == 4) {
                if (cosmetic_n >= def.MAX_COSMETICS) {
                    err_line = line_no;
                    return error.Overflow;
                }
                var cr = def.CosmeticRow{ .name = "", .price = 0, .unlock = 0 };
                try parseCosmetic(fields[0..], fn_count, line_no, &cr);
                tmp.cosmetics[cosmetic_n] = cr;
                cosmetic_src[cosmetic_n] = line_no;
                cosmetic_n += 1;
            } else if (section == 5) {
                try parseEncounter(fields[0..], fn_count, line_no, &tmp);
            } else if (section == 6) {
                try parseZone(fields[0..], fn_count, line_no, &tmp);
            } else {
                return failLine(line_no);
            }
        } else {
            return failLine(line_no);
        }

        pos = if (eol < content.len) eol + 1 else content.len;
    }
    last_line = line_no;

    if (!header_ok) {
        err_line = 1;
        return error.DamagedLine;
    }
    if (text_active) {
        finishTextValue(content, &tmp, text_val_start, text_val_end);
        text_active = false;
    }

    tmp.tool_count = @intCast(i32, tool_n);
    tmp.upgrade_count = @intCast(i32, upgrade_n);
    tmp.cosmetic_count = @intCast(i32, cosmetic_n);

    var ti: usize = 0;
    var text_bytes: usize = 0;
    while (ti < @intCast(usize, tmp.text_count)) : (ti += 1) {
        text_bytes += tmp.text_val[ti].len;
    }
    if (text_bytes > def.MAX_TEXT_BYTES) {
        err_line = if (text_section_line > 0) text_section_line else 1;
        return error.Overflow;
    }

    try packRules(&tmp, &rule_owner, &rule_row, &rule_in_line, rule_n);

    tmp.loaded = 1;
    lines_ready = true;
    tables.* = tmp;
    return;
}

// ---- field-by-field dump --------------------------------------------------

fn bInt(out: *buf_mod.Buf, v: i32) void {
    var tmp: [16]u8 = undefined;
    var n: i64 = @intCast(i64, v);
    var neg: bool = false;
    if (n < 0) {
        neg = true;
        n = -n;
    }
    var t: usize = 0;
    if (n == 0) {
        tmp[0] = '0';
        t = 1;
    } else {
        while (n > 0) : (n = n / 10) {
            tmp[t] = @intCast(u8, @intCast(i32, '0') + @intCast(i32, @intCast(u32, n % 10)));
            t += 1;
        }
    }
    if (neg) buf_mod.appendByte(out, '-') catch {};
    while (t > 0) {
        t -= 1;
        buf_mod.appendByte(out, tmp[t]) catch {};
    }
}

fn bUint(out: *buf_mod.Buf, v: u32) void {
    var tmp: [16]u8 = undefined;
    var n: u64 = @intCast(u64, v);
    var t: usize = 0;
    if (n == 0) {
        tmp[0] = '0';
        t = 1;
    } else {
        while (n > 0) : (n = n / 10) {
            tmp[t] = @intCast(u8, @intCast(i32, '0') + @intCast(i32, @intCast(u32, n % 10)));
            t += 1;
        }
    }
    while (t > 0) {
        t -= 1;
        buf_mod.appendByte(out, tmp[t]) catch {};
    }
}

fn kvStr(out: *buf_mod.Buf, first: *bool, key: []const u8, val: []const u8) void {
    if (!first.*) buf_mod.append(out, ",") catch {};
    first.* = false;
    buf_mod.append(out, key) catch {};
    buf_mod.append(out, "=") catch {};
    buf_mod.append(out, val) catch {};
}

fn kvInt(out: *buf_mod.Buf, first: *bool, key: []const u8, v: i32) void {
    if (!first.*) buf_mod.append(out, ",") catch {};
    first.* = false;
    buf_mod.append(out, key) catch {};
    buf_mod.append(out, "=") catch {};
    bInt(out, v);
}

fn kvUint(out: *buf_mod.Buf, first: *bool, key: []const u8, v: u32) void {
    if (!first.*) buf_mod.append(out, ",") catch {};
    first.* = false;
    buf_mod.append(out, key) catch {};
    buf_mod.append(out, "=") catch {};
    bUint(out, v);
}

fn nl(out: *buf_mod.Buf) void {
    buf_mod.appendByte(out, '\n') catch {};
}

pub fn dumpDefs(t: *const def.Tables, out: *buf_mod.Buf) void {
    buf_mod.append(out, "format=2") catch {};
    nl(out);

    buf_mod.append(out, "[defs]") catch {};
    nl(out);
    var i: usize = 0;
    while (i < @intCast(usize, t.def_count)) : (i += 1) {
        const d = t.defs[i];
        var first: bool = true;
        kvInt(out, &first, "id", d.id);
        kvStr(out, &first, "name", d.name[0..@intCast(usize, d.name_len)]);
        kvInt(out, &first, "name_len", d.name_len);
        kvInt(out, &first, "family", d.family);
        kvInt(out, &first, "role", d.role);
        kvUint(out, &first, "zone_mask", d.zone_mask);
        kvUint(out, &first, "phase_mask", d.phase_mask);
        kvInt(out, &first, "hp", d.hp);
        kvInt(out, &first, "resolve", d.resolve);
        kvInt(out, &first, "speed", d.speed);
        kvInt(out, &first, "attack", d.attack);
        kvInt(out, &first, "thrash_regen", d.thrash_regen);
        kvInt(out, &first, "despair_regen", d.despair_regen);
        kvInt(out, &first, "armor_pct", d.armor_pct);
        kvUint(out, &first, "flags", d.flags);
        kvInt(out, &first, "resist_restrain_pct", d.resist_restrain_pct);
        kvInt(out, &first, "blind_chance", d.blind_chance);
        kvInt(out, &first, "subdue_chance", d.subdue_chance);
        kvInt(out, &first, "discharge_stat", d.discharge_stat);
        kvInt(out, &first, "discharge_th", d.discharge_th);
        kvInt(out, &first, "discharge_dmg", d.discharge_dmg);
        kvInt(out, &first, "armor_below_th", d.armor_below_th);
        kvInt(out, &first, "armor_below_pct", d.armor_below_pct);
        kvInt(out, &first, "speed_below_stat", d.speed_below_stat);
        kvInt(out, &first, "speed_below_th", d.speed_below_th);
        kvInt(out, &first, "speed_below_add", d.speed_below_add);
        kvInt(out, &first, "atk_below_th", d.atk_below_th);
        kvInt(out, &first, "atk_below_pct", d.atk_below_pct);
        kvInt(out, &first, "flee_kind", d.flee_kind);
        kvInt(out, &first, "flee_th", d.flee_th);
        kvInt(out, &first, "grudge_family", d.grudge_family);
        kvInt(out, &first, "grudge_kind", d.grudge_kind);
        kvInt(out, &first, "grudge_value", d.grudge_value);

        var k: usize = 0;
        while (k < def.MAX_DROP_LINES) : (k += 1) {
            kvInt(out, &first, SUB_PART[k], d.sub[k].part);
            kvInt(out, &first, SUB_COUNT[k], d.sub[k].count);
        }
        k = 0;
        while (k < def.MAX_DROP_LINES) : (k += 1) {
            kvInt(out, &first, KILL_PART[k], d.kill[k].part);
            kvInt(out, &first, KILL_COUNT[k], d.kill[k].count);
        }
        k = 0;
        while (k < def.MAX_DROP_LINES) : (k += 1) {
            kvInt(out, &first, OVER_PART[k], d.over[k].part);
            kvInt(out, &first, OVER_COUNT[k], d.over[k].count);
        }
        kvInt(out, &first, "sale", d.sale);
        kvInt(out, &first, "respawn_sub", d.respawn[0]);
        kvInt(out, &first, "respawn_kill", d.respawn[1]);
        kvInt(out, &first, "respawn_over", d.respawn[2]);
        kvInt(out, &first, "counter_tool", d.counter_tool);
        kvInt(out, &first, "rule_start", d.rule_start);
        kvInt(out, &first, "rule_count", d.rule_count);
        nl(out);
    }

    buf_mod.append(out, "[rules]") catch {};
    nl(out);
    i = 0;
    while (i < @intCast(usize, t.rule_count)) : (i += 1) {
        const r = t.rules[i];
        var first: bool = true;
        kvInt(out, &first, "cond_op", r.cond_op);
        kvInt(out, &first, "cond_a", r.cond_a);
        kvInt(out, &first, "cond_b", r.cond_b);
        kvInt(out, &first, "effect_op", r.effect_op);
        kvInt(out, &first, "effect_a", r.effect_a);
        kvInt(out, &first, "effect_b", r.effect_b);
        kvInt(out, &first, "timing", r.timing);
        nl(out);
    }

    buf_mod.append(out, "[tools]") catch {};
    nl(out);
    i = 0;
    while (i < @intCast(usize, t.tool_count)) : (i += 1) {
        const tr = t.tools[i];
        var first: bool = true;
        kvInt(out, &first, "id", tr.id);
        kvInt(out, &first, "kind", tr.kind);
        var k: usize = 0;
        while (k < 3) : (k += 1) {
            kvInt(out, &first, COST_KIND[k], tr.cost[k].kind);
            kvInt(out, &first, COST_AMT[k], tr.cost[k].amt);
        }
        nl(out);
    }

    buf_mod.append(out, "[upgrades]") catch {};
    nl(out);
    i = 0;
    while (i < @intCast(usize, t.upgrade_count)) : (i += 1) {
        const ur = t.upgrades[i];
        var first: bool = true;
        kvInt(out, &first, "axis", ur.axis);
        kvInt(out, &first, "tier", ur.tier);
        var k: usize = 0;
        while (k < 3) : (k += 1) {
            kvInt(out, &first, COST_KIND[k], ur.cost[k].kind);
            kvInt(out, &first, COST_AMT[k], ur.cost[k].amt);
        }
        nl(out);
    }

    buf_mod.append(out, "[cosmetics]") catch {};
    nl(out);
    i = 0;
    while (i < @intCast(usize, t.cosmetic_count)) : (i += 1) {
        const cr = t.cosmetics[i];
        var first: bool = true;
        kvStr(out, &first, "name", cr.name);
        kvInt(out, &first, "price", cr.price);
        kvInt(out, &first, "unlock", cr.unlock);
        nl(out);
    }

    buf_mod.append(out, "[encounters]") catch {};
    nl(out);
    var z: i32 = 0;
    while (z < @intCast(i32, def.MAX_ZONES)) : (z += 1) {
        var ph: i32 = 0;
        while (ph < 2) : (ph += 1) {
            const ci: usize = @intCast(usize, z) * 2 + @intCast(usize, ph);
            const base: usize = @intCast(usize, z) * 2 * def.MAX_ENCOUNTER +
                @intCast(usize, ph) * def.MAX_ENCOUNTER;
            var j: usize = 0;
            while (j < @intCast(usize, t.enc_count[ci])) : (j += 1) {
                const er = t.encounters[base + j];
                var first: bool = true;
                kvInt(out, &first, "zone", z);
                kvInt(out, &first, "phase", ph);
                kvInt(out, &first, "def_index", er.def_index);
                kvInt(out, &first, "weight", er.weight);
                nl(out);
            }
        }
    }

    buf_mod.append(out, "[zones]") catch {};
    nl(out);
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        var first: bool = true;
        kvInt(out, &first, "id", @intCast(i32, i));
        kvInt(out, &first, "cost", t.zone_cost[i]);
        kvInt(out, &first, "boss", t.zone_boss[i]);
        nl(out);
    }

    buf_mod.append(out, "[text-keys]") catch {};
    nl(out);
    i = 0;
    while (i < @intCast(usize, t.text_count)) : (i += 1) {
        var first: bool = true;
        kvStr(out, &first, "key", t.text_key[i]);
        nl(out);
    }
}
