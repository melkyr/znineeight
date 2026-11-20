// fallback_emit.zig — deterministic Z98 emission for the compiled fallback.
//
// `undtool --emit-fallback <outdir>` loads data.z98 and writes the checked-in
// fallback_rows.zig module. The output is byte-deterministic: it depends only
// on the loaded tables (row order and values), never on time or addresses.

const buf_mod = @import("std_buf.zig");
const def = @import("def.zig");

fn put(out: *buf_mod.Buf, s: []const u8) void {
    buf_mod.append(out, s) catch {};
}

fn putInt(out: *buf_mod.Buf, v: i32) void {
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
    if (neg) put(out, "-");
    while (t > 0) {
        t -= 1;
        buf_mod.appendByte(out, tmp[t]) catch {};
    }
}

fn putUint(out: *buf_mod.Buf, v: u32) void {
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

fn putName(out: *buf_mod.Buf, d: def.CreatureDef) void {
    put(out, "[def.MAX_NAME_LEN]u8{ ");
    var i: usize = 0;
    while (i < def.MAX_NAME_LEN) : (i += 1) {
        if (i != 0) put(out, ", ");
        putInt(out, @intCast(i32, d.name[i]));
    }
    put(out, " }");
}

fn putDrop(out: *buf_mod.Buf, l: def.DropLine) void {
    put(out, "def.DropLine{ .part = ");
    putInt(out, l.part);
    put(out, ", .count = ");
    putInt(out, l.count);
    put(out, " }");
}

fn putDrops(out: *buf_mod.Buf, label: []const u8, rows: [def.MAX_DROP_LINES]def.DropLine) void {
    put(out, "        .");
    put(out, label);
    put(out, " = [def.MAX_DROP_LINES]def.DropLine{\n");
    var i: usize = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        put(out, "            ");
        putDrop(out, rows[i]);
        put(out, ",\n");
    }
    put(out, "        },\n");
}

fn putDef(out: *buf_mod.Buf, d: def.CreatureDef) void {
    put(out, "    def.CreatureDef{\n");
    put(out, "        .id = ");
    putInt(out, d.id);
    put(out, ",\n        .name = ");
    putName(out, d);
    put(out, ",\n        .name_len = ");
    putInt(out, d.name_len);
    put(out, ",\n        .family = ");
    putInt(out, d.family);
    put(out, ",\n        .role = ");
    putInt(out, d.role);
    put(out, ",\n        .zone_mask = ");
    putUint(out, d.zone_mask);
    put(out, ",\n        .phase_mask = ");
    putUint(out, d.phase_mask);
    put(out, ",\n        .hp = ");
    putInt(out, d.hp);
    put(out, ",\n        .resolve = ");
    putInt(out, d.resolve);
    put(out, ",\n        .speed = ");
    putInt(out, d.speed);
    put(out, ",\n        .attack = ");
    putInt(out, d.attack);
    put(out, ",\n        .thrash_regen = ");
    putInt(out, d.thrash_regen);
    put(out, ",\n        .despair_regen = ");
    putInt(out, d.despair_regen);
    put(out, ",\n        .armor_pct = ");
    putInt(out, d.armor_pct);
    put(out, ",\n        .flags = ");
    putUint(out, d.flags);
    put(out, ",\n        .resist_restrain_pct = ");
    putInt(out, d.resist_restrain_pct);
    put(out, ",\n        .blind_chance = ");
    putInt(out, d.blind_chance);
    put(out, ",\n        .subdue_chance = ");
    putInt(out, d.subdue_chance);
    put(out, ",\n        .discharge_stat = ");
    putInt(out, d.discharge_stat);
    put(out, ",\n        .discharge_th = ");
    putInt(out, d.discharge_th);
    put(out, ",\n        .discharge_dmg = ");
    putInt(out, d.discharge_dmg);
    put(out, ",\n        .armor_below_th = ");
    putInt(out, d.armor_below_th);
    put(out, ",\n        .armor_below_pct = ");
    putInt(out, d.armor_below_pct);
    put(out, ",\n        .speed_below_stat = ");
    putInt(out, d.speed_below_stat);
    put(out, ",\n        .speed_below_th = ");
    putInt(out, d.speed_below_th);
    put(out, ",\n        .speed_below_add = ");
    putInt(out, d.speed_below_add);
    put(out, ",\n        .atk_below_th = ");
    putInt(out, d.atk_below_th);
    put(out, ",\n        .atk_below_pct = ");
    putInt(out, d.atk_below_pct);
    put(out, ",\n        .flee_kind = ");
    putInt(out, d.flee_kind);
    put(out, ",\n        .flee_th = ");
    putInt(out, d.flee_th);
    put(out, ",\n        .grudge_family = ");
    putInt(out, d.grudge_family);
    put(out, ",\n        .grudge_kind = ");
    putInt(out, d.grudge_kind);
    put(out, ",\n        .grudge_value = ");
    putInt(out, d.grudge_value);
    put(out, ",\n");
    putDrops(out, "sub", d.sub);
    putDrops(out, "kill", d.kill);
    putDrops(out, "over", d.over);
    put(out, "        .sale = ");
    putInt(out, d.sale);
    put(out, ",\n        .respawn = [3]i32{ ");
    putInt(out, d.respawn[0]);
    put(out, ", ");
    putInt(out, d.respawn[1]);
    put(out, ", ");
    putInt(out, d.respawn[2]);
    put(out, " },\n        .counter_tool = ");
    putInt(out, d.counter_tool);
    put(out, ",\n        .rule_start = ");
    putInt(out, d.rule_start);
    put(out, ",\n        .rule_count = ");
    putInt(out, d.rule_count);
    put(out, ",\n    },\n");
}

fn putCost(out: *buf_mod.Buf, c: def.CostSlot) void {
    put(out, "def.CostSlot{ .kind = ");
    putInt(out, c.kind);
    put(out, ", .amt = ");
    putInt(out, c.amt);
    put(out, " }");
}

fn putCosts(out: *buf_mod.Buf, cost: [3]def.CostSlot) void {
    put(out, "[3]def.CostSlot{ ");
    putCost(out, cost[0]);
    put(out, ", ");
    putCost(out, cost[1]);
    put(out, ", ");
    putCost(out, cost[2]);
    put(out, " }");
}

fn putRule(out: *buf_mod.Buf, r: def.Rule) void {
    put(out, "    behavior.Rule{ .cond_op = ");
    putInt(out, r.cond_op);
    put(out, ", .cond_a = ");
    putInt(out, r.cond_a);
    put(out, ", .cond_b = ");
    putInt(out, r.cond_b);
    put(out, ", .effect_op = ");
    putInt(out, r.effect_op);
    put(out, ", .effect_a = ");
    putInt(out, r.effect_a);
    put(out, ", .effect_b = ");
    putInt(out, r.effect_b);
    put(out, ", .timing = ");
    putInt(out, r.timing);
    put(out, " },\n");
}

fn putEncArray(out: *buf_mod.Buf, name: []const u8, rows: []const def.EncounterRow) void {
    put(out, "pub const ");
    put(out, name);
    put(out, " = [");
    putInt(out, @intCast(i32, rows.len));
    put(out, "]def.EncounterRow{\n");
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        put(out, "    def.EncounterRow{ .def_index = ");
        putInt(out, rows[i].def_index);
        put(out, ", .weight = ");
        putInt(out, rows[i].weight);
        put(out, " },\n");
    }
    put(out, "};\n\n");
}

fn encName(zone: usize, phase: usize, out: []u8) []const u8 {
    var at: usize = 0;
    out[at] = 'E';
    at += 1;
    out[at] = 'N';
    at += 1;
    out[at] = 'C';
    at += 1;
    out[at] = '_';
    at += 1;
    out[at] = 'Z';
    at += 1;
    out[at] = @intCast(u8, @intCast(i32, '0') + @intCast(i32, zone));
    at += 1;
    out[at] = '_';
    at += 1;
    if (phase == 0) {
        out[at] = 'D';
        out[at + 1] = 'A';
        out[at + 2] = 'Y';
        return out[0 .. at + 3];
    }
    out[at] = 'N';
    out[at + 1] = 'I';
    out[at + 2] = 'G';
    out[at + 3] = 'H';
    out[at + 4] = 'T';
    return out[0 .. at + 5];
}

fn encCount(t: *const def.Tables, zone: usize, phase: usize) usize {
    const ci: usize = zone * 2 + phase;
    const n = t.enc_count[ci];
    if (n <= 0) return 0;
    return @intCast(usize, n);
}

fn encRows(t: *const def.Tables, zone: usize, phase: usize, n: usize) []const def.EncounterRow {
    const base: usize = zone * 2 * def.MAX_ENCOUNTER + phase * def.MAX_ENCOUNTER;
    return t.encounters[base .. base + n];
}

pub fn emit(t: *const def.Tables, out: *buf_mod.Buf) void {

    put(out, "// fallback_rows.zig - generated by undtool --emit-fallback; do not edit.\n");
    put(out, "// Source: data.z98. Deterministic output (row order and values only).\n\n");
    put(out, "const def = @import(\"def.zig\");\n");
    put(out, "const behavior = @import(\"behavior.zig\");\n\n");
    put(out, "pub const ROLE_COMMON: i32 = 1;\n");
    put(out, "pub const ROLE_NAMED: i32 = 2;\n");
    put(out, "pub const ROLE_RARE: i32 = 3;\n");
    put(out, "pub const ROLE_BOSS: i32 = 4;\n\n");
    put(out, "pub const STAT_HP: i32 = 1;\n");
    put(out, "pub const STAT_RES: i32 = 2;\n\n");
    put(out, "pub const FAMILY_EEL: i32 = 1;\n");
    put(out, "pub const FAMILY_TUNA: i32 = 2;\n");
    put(out, "pub const FAMILY_CRAB: i32 = 3;\n");
    put(out, "pub const FAMILY_JELLY: i32 = 4;\n");
    put(out, "pub const FAMILY_BARNACLE: i32 = 5;\n");
    put(out, "pub const FAMILY_RAY: i32 = 7;\n");
    put(out, "pub const FAMILY_SQUID: i32 = 8;\n");
    put(out, "pub const FAMILY_ANGLER: i32 = 9;\n");
    put(out, "pub const FAMILY_ANEMONE: i32 = 10;\n");
    put(out, "pub const FAMILY_PERCH: i32 = 11;\n");
    put(out, "pub const FAMILY_WRASSE: i32 = 12;\n");
    put(out, "pub const FAMILY_BOSS: i32 = 13;\n\n");
    put(out, "pub const GRUDGE_RES: i32 = 1;\n");
    put(out, "pub const GRUDGE_ARMOR: i32 = 2;\n\n");
    put(out, "pub const PART_SHELL_CHIP: i32 = 1;\n");
    put(out, "pub const PART_PLATE_SCRAP: i32 = 2;\n");
    put(out, "pub const PART_GLAND_SAC: i32 = 3;\n");
    put(out, "pub const PART_BRINE_VIAL: i32 = 4;\n");
    put(out, "pub const PART_CORAL_BUD: i32 = 5;\n");
    put(out, "pub const PART_GLOW_POLYP: i32 = 6;\n");
    put(out, "pub const PART_GLASS_PANE: i32 = 7;\n");
    put(out, "pub const PART_HOOKED_BARBEL: i32 = 8;\n");
    put(out, "pub const PART_STEEL_FINS: i32 = 9;\n\n");
    put(out, "pub const PHASE_DAY: i32 = 0;\n");
    put(out, "pub const PHASE_NIGHT: i32 = 1;\n\n");

    put(out, "pub const DEFS = [");
    putInt(out, t.def_count);
    put(out, "]def.CreatureDef{\n");
    var i: usize = 0;
    while (i < @intCast(usize, t.def_count)) : (i += 1) {
        putDef(out, t.defs[i]);
    }
    put(out, "};\n\n");

    put(out, "pub const RULES = [");
    putInt(out, t.rule_count);
    put(out, "]behavior.Rule{\n");
    i = 0;
    while (i < @intCast(usize, t.rule_count)) : (i += 1) {
        putRule(out, t.rules[i]);
    }
    put(out, "};\n\n");

    put(out, "pub const TOOLS = [");
    putInt(out, t.tool_count);
    put(out, "]def.ToolRow{\n");
    i = 0;
    while (i < @intCast(usize, t.tool_count)) : (i += 1) {
        const tr = t.tools[i];
        put(out, "    def.ToolRow{ .id = ");
        putInt(out, tr.id);
        put(out, ", .kind = ");
        putInt(out, tr.kind);
        put(out, ", .cost = ");
        putCosts(out, tr.cost);
        put(out, " },\n");
    }
    put(out, "};\n\n");

    put(out, "pub const UPGRADES = [");
    putInt(out, t.upgrade_count);
    put(out, "]def.UpgradeRow{\n");
    i = 0;
    while (i < @intCast(usize, t.upgrade_count)) : (i += 1) {
        const ur = t.upgrades[i];
        put(out, "    def.UpgradeRow{ .axis = ");
        putInt(out, ur.axis);
        put(out, ", .tier = ");
        putInt(out, ur.tier);
        put(out, ", .cost = ");
        putCosts(out, ur.cost);
        put(out, " },\n");
    }
    put(out, "};\n\n");

    put(out, "pub const COSMETICS = [");
    putInt(out, t.cosmetic_count);
    put(out, "]def.CosmeticRow{\n");
    i = 0;
    while (i < @intCast(usize, t.cosmetic_count)) : (i += 1) {
        const cr = t.cosmetics[i];
        put(out, "    def.CosmeticRow{ .name = \"");
        put(out, cr.name);
        put(out, "\", .price = ");
        putInt(out, cr.price);
        put(out, ", .unlock = ");
        putInt(out, cr.unlock);
        put(out, " },\n");
    }
    put(out, "};\n\n");

    put(out, "pub const ZONE_COST = [def.MAX_ZONES]i32{ ");
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        if (i != 0) put(out, ", ");
        putInt(out, t.zone_cost[i]);
    }
    put(out, " };\n");
    put(out, "pub const ZONE_IS_BOSS = [def.MAX_ZONES]i32{ ");
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        if (i != 0) put(out, ", ");
        putInt(out, t.zone_boss[i]);
    }
    put(out, " };\n\n");

    put(out, "pub const EMPTY = [0]def.EncounterRow{};\n\n");

    var name_buf: [16]u8 = undefined;
    var z: usize = 0;
    while (z < def.MAX_ZONES) : (z += 1) {
        var ph: usize = 0;
        while (ph < 2) : (ph += 1) {
            const n = encCount(t, z, ph);
            if (n == 0) continue;
            const name = encName(z, ph, name_buf[0..]);
            putEncArray(out, name, encRows(t, z, ph, n));
        }
    }

    put(out, "pub const ENCOUNTERS = [def.MAX_ZONES][2][]const def.EncounterRow{\n");
    z = 0;
    while (z < def.MAX_ZONES) : (z += 1) {
        put(out, "    [2][]const def.EncounterRow{ ");
        var ph: usize = 0;
        while (ph < 2) : (ph += 1) {
            if (ph != 0) put(out, ", ");
            const n = encCount(t, z, ph);
            if (n == 0) {
                put(out, "EMPTY[0..]");
            } else {
                put(out, encName(z, ph, name_buf[0..]));
                put(out, "[0..]");
            }
        }
        put(out, " },\n");
    }
    put(out, "};\n");
}
