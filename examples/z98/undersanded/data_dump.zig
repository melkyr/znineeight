// data_dump.zig — UNDERSANDED data.z98 field-by-field dump (spec §25.10).
//
// Deterministic format=2 text image of a Tables struct. Uses the same key
// names as the schema parser so a dumped image reloads cleanly.

const def = @import("def.zig");
const buf_mod = @import("std_buf.zig");
const schema = @import("data_schema.zig");

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
            kvInt(out, &first, schema.SUB_PART[k], d.sub[k].part);
            kvInt(out, &first, schema.SUB_COUNT[k], d.sub[k].count);
        }
        k = 0;
        while (k < def.MAX_DROP_LINES) : (k += 1) {
            kvInt(out, &first, schema.KILL_PART[k], d.kill[k].part);
            kvInt(out, &first, schema.KILL_COUNT[k], d.kill[k].count);
        }
        k = 0;
        while (k < def.MAX_DROP_LINES) : (k += 1) {
            kvInt(out, &first, schema.OVER_PART[k], d.over[k].part);
            kvInt(out, &first, schema.OVER_COUNT[k], d.over[k].count);
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
            kvInt(out, &first, schema.COST_KIND[k], tr.cost[k].kind);
            kvInt(out, &first, schema.COST_AMT[k], tr.cost[k].amt);
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
            kvInt(out, &first, schema.COST_KIND[k], ur.cost[k].kind);
            kvInt(out, &first, schema.COST_AMT[k], ur.cost[k].amt);
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
