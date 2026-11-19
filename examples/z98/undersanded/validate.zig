// validate.zig — UNDERSANDED M6 post-load invariants (spec §25.1/§25.2/§25.10).
//
// validateAll runs after loadFile and returns the same LoadErr set. Structure
// first, first failure wins: header/version, creatures, rules, tools,
// encounters, zones, text, cosmetics, then the 5×3 upgrade grid. Line probes
// come from data.zig when the Tables image was loaded from a file; a fallback
// or synthetic image reports line 0.

const def = @import("def.zig");
const data = @import("data.zig");

const ROLE_MIN: i32 = 1;
const ROLE_MAX: i32 = 3;
const FAMILY_MIN: i32 = 1;
const FAMILY_MAX: i32 = 12;
const COND_MIN: i32 = 1;
const COND_MAX: i32 = 5;
const EFFECT_MIN: i32 = 1;
const EFFECT_MAX: i32 = 10;
const TIMING_MIN: i32 = 0;
const TIMING_MAX: i32 = 1;
const PART_MAX: i32 = 13;
const DROP_MAX: i32 = 99;
const COST_KIND_MAX: i32 = 9;

fn at(line: i32) void {
    data.err_line = line;
}

fn same(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn dropsOk(dl: []const def.DropLine) bool {
    var k: usize = 0;
    while (k < dl.len) : (k += 1) {
        const p = dl[k].part;
        const c = dl[k].count;
        if (p < 0 or p > PART_MAX) return false;
        if (c < 0 or c > DROP_MAX) return false;
    }
    return true;
}

pub fn validateAll(t: *const def.Tables) data.LoadErr!void {
    data.err_line = 0;

    if (t.content_version != 2) {
        at(data.headerSrcLine());
        return error.DamagedLine;
    }

    // ---- creatures --------------------------------------------------------
    if (t.def_count < 0) {
        at(data.sectionSrcLine(0));
        return error.DamagedLine;
    }
    if (t.def_count > @intCast(i32, def.MAX_CREATURES)) {
        at(data.sectionSrcLine(0));
        return error.Overflow;
    }

    var i: i32 = 0;
    while (i < t.def_count) : (i += 1) {
        const d = t.defs[@intCast(usize, i)];
        const line = data.defSrcLine(i);

        if (d.name_len <= 0 or d.name_len > @intCast(i32, def.MAX_NAME_LEN)) {
            at(line);
            return error.DamagedLine;
        }
        var nb: usize = 0;
        while (nb < @intCast(usize, d.name_len)) : (nb += 1) {
            const b = d.name[nb];
            if (b < 0x20 or b > 0x7e) {
                at(line);
                return error.DamagedLine;
            }
        }
        if (d.family < FAMILY_MIN or d.family > FAMILY_MAX) {
            at(line);
            return error.BadRef;
        }
        if (d.role < ROLE_MIN or d.role > ROLE_MAX) {
            at(line);
            return error.BadRef;
        }
        if (d.zone_mask >= 4096) {
            at(line);
            return error.BadRef;
        }
        if (d.phase_mask == 0) {
            at(line);
            return error.BadRef;
        }
        if (d.phase_mask > 3) {
            at(line);
            return error.BadRef;
        }

        const is_boss = (d.flags % 2) != 0;
        if (is_boss) {
            if (d.subdue_chance != -1) {
                at(line);
                return error.BadSentinel;
            }
        } else {
            if (d.subdue_chance < 0 or d.subdue_chance > 100) {
                at(line);
                return error.BadSentinel;
            }
        }

        if (d.sale <= 0) {
            at(line);
            return error.BadRef;
        }
        if (d.respawn[0] > d.respawn[1] or d.respawn[1] > d.respawn[2]) {
            at(line);
            return error.BadRef;
        }
        if (!dropsOk(d.sub[0..]) or !dropsOk(d.kill[0..]) or !dropsOk(d.over[0..])) {
            at(line);
            return error.BadRef;
        }
    }

    i = 0;
    while (i < t.def_count) : (i += 1) {
        var j: i32 = i + 1;
        while (j < t.def_count) : (j += 1) {
            const a = t.defs[@intCast(usize, i)];
            const b = t.defs[@intCast(usize, j)];
            if (a.id == b.id) {
                at(data.defSrcLine(j));
                return error.BadRef;
            }
            const an = a.name[0..@intCast(usize, a.name_len)];
            const bn = b.name[0..@intCast(usize, b.name_len)];
            if (same(an, bn)) {
                at(data.defSrcLine(j));
                return error.BadRef;
            }
        }
    }

    // ---- rules ------------------------------------------------------------
    if (t.rule_count < 0) {
        at(data.sectionSrcLine(1));
        return error.DamagedLine;
    }
    if (t.rule_count > @intCast(i32, def.MAX_RULES)) {
        at(data.sectionSrcLine(1));
        return error.Overflow;
    }

    var cov: [def.MAX_RULES]i32 = undefined;
    var k: usize = 0;
    while (k < def.MAX_RULES) : (k += 1) {
        cov[k] = 0;
    }

    i = 0;
    while (i < t.def_count) : (i += 1) {
        const d = t.defs[@intCast(usize, i)];
        const line = data.defSrcLine(i);
        if (d.rule_start < 0 or d.rule_count < 0 or
            d.rule_start > t.rule_count or d.rule_count > t.rule_count - d.rule_start) {
            at(line);
            return error.BadRef;
        }
        var m: i32 = 0;
        while (m < d.rule_count) : (m += 1) {
            const idx: i32 = d.rule_start + m;
            cov[@intCast(usize, idx)] += 1;
        }
    }

    k = 0;
    while (k < @intCast(usize, t.rule_count)) : (k += 1) {
        if (cov[k] != 1) {
            at(data.ruleSrcLine(@intCast(i32, k)));
            return error.BadRef;
        }
    }

    i = 0;
    while (i < t.rule_count) : (i += 1) {
        const r = t.rules[@intCast(usize, i)];
        const line = data.ruleSrcLine(i);
        if (r.cond_op < COND_MIN or r.cond_op > COND_MAX) {
            at(line);
            return error.BadRef;
        }
        if (r.effect_op < EFFECT_MIN or r.effect_op > EFFECT_MAX) {
            at(line);
            return error.BadRef;
        }
        if (r.timing < TIMING_MIN or r.timing > TIMING_MAX) {
            at(line);
            return error.BadRef;
        }
    }

    // ---- tools ------------------------------------------------------------
    if (t.tool_count < 0) {
        at(data.sectionSrcLine(2));
        return error.DamagedLine;
    }
    if (t.tool_count > @intCast(i32, def.MAX_TOOLS)) {
        at(data.sectionSrcLine(2));
        return error.Overflow;
    }

    i = 0;
    while (i < t.tool_count) : (i += 1) {
        const tr = t.tools[@intCast(usize, i)];
        const line = data.toolSrcLine(i);
        if (tr.id < 1 or tr.id > 7) {
            at(line);
            return error.BadRef;
        }
        if (tr.kind < 0 or tr.kind > 1) {
            at(line);
            return error.BadRef;
        }
        var c: usize = 0;
        while (c < 3) : (c += 1) {
            const kind = tr.cost[c].kind;
            if (kind < 0 or kind > COST_KIND_MAX) {
                at(line);
                return error.BadRef;
            }
            if (kind >= 1) {
                var m: usize = 0;
                while (m < c) : (m += 1) {
                    if (tr.cost[m].kind == kind) {
                        at(line);
                        return error.BadRef;
                    }
                }
            }
        }
    }

    i = 0;
    while (i < t.tool_count) : (i += 1) {
        var j: i32 = i + 1;
        while (j < t.tool_count) : (j += 1) {
            if (t.tools[@intCast(usize, i)].id == t.tools[@intCast(usize, j)].id) {
                at(data.toolSrcLine(j));
                return error.BadRef;
            }
        }
    }

    // ---- encounters -------------------------------------------------------
    var ci: i32 = 0;
    while (ci < @intCast(i32, def.MAX_ZONES * 2)) : (ci += 1) {
        const n = t.enc_count[@intCast(usize, ci)];
        if (n < 0) {
            at(data.sectionSrcLine(5));
            return error.DamagedLine;
        }
        if (n > @intCast(i32, def.MAX_ENCOUNTER)) {
            at(data.sectionSrcLine(5));
            return error.Overflow;
        }
    }

    var z: i32 = 0;
    while (z < @intCast(i32, def.MAX_ZONES)) : (z += 1) {
        var ph: i32 = 0;
        while (ph < 2) : (ph += 1) {
            const bucket: i32 = z * 2 + ph;
            const base: i32 = z * 2 * @intCast(i32, def.MAX_ENCOUNTER) +
                ph * @intCast(i32, def.MAX_ENCOUNTER);
            const n = t.enc_count[@intCast(usize, bucket)];
            var sum: i32 = 0;
            var j: i32 = 0;
            while (j < n) : (j += 1) {
                const er = t.encounters[@intCast(usize, base + j)];
                const line = data.encSrcLine(base + j);
                if (er.def_index < 0 or er.def_index >= t.def_count) {
                    at(line);
                    return error.BadRef;
                }
                if (er.weight <= 0) {
                    at(line);
                    return error.BadRef;
                }
                sum += er.weight;
            }
            if (n > 0 and sum != 100) {
                at(data.encSrcLine(base));
                return error.BadRef;
            }
        }
    }

    // ---- zones ------------------------------------------------------------
    z = 0;
    while (z < @intCast(i32, def.MAX_ZONES)) : (z += 1) {
        const line = data.zoneSrcLine(z);
        if (t.zone_cost[@intCast(usize, z)] < 0) {
            at(line);
            return error.BadRef;
        }
        const boss = t.zone_boss[@intCast(usize, z)];
        if (boss != 0 and boss != 1) {
            at(line);
            return error.BadRef;
        }
    }

    // ---- text -------------------------------------------------------------
    if (t.text_count < 0) {
        at(data.sectionSrcLine(7));
        return error.DamagedLine;
    }
    if (t.text_count > @intCast(i32, def.MAX_TEXT_KEYS)) {
        at(data.sectionSrcLine(7));
        return error.TooMany;
    }

    var text_bytes: usize = 0;
    i = 0;
    while (i < t.text_count) : (i += 1) {
        const key = t.text_key[@intCast(usize, i)];
        if (!data.textKeyKnown(key)) {
            at(data.sectionSrcLine(7));
            return error.DamagedLine;
        }
        text_bytes += t.text_val[@intCast(usize, i)].len;
    }
    if (text_bytes > def.MAX_TEXT_BYTES) {
        at(data.sectionSrcLine(7));
        return error.Overflow;
    }
    if (t.loaded != 0 or t.text_count > 0) {
        var has_manual: bool = false;
        var manual_empty: bool = false;
        i = 0;
        while (i < t.text_count) : (i += 1) {
            if (same(t.text_key[@intCast(usize, i)], "manual.1")) {
                has_manual = true;
                if (t.text_val[@intCast(usize, i)].len == 0) manual_empty = true;
            }
        }
        if (!has_manual or manual_empty) {
            const sec = data.sectionSrcLine(7);
            if (sec > 0) {
                at(sec);
            } else if (t.loaded != 0) {
                at(data.lastSrcLine());
            } else {
                at(0);
            }
            return error.DamagedLine;
        }
    }

    // ---- cosmetics --------------------------------------------------------
    if (t.cosmetic_count < 0) {
        at(data.sectionSrcLine(4));
        return error.DamagedLine;
    }
    if (t.cosmetic_count > @intCast(i32, def.MAX_COSMETICS)) {
        at(data.sectionSrcLine(4));
        return error.Overflow;
    }
    if (t.cosmetic_count != @intCast(i32, def.MAX_COSMETICS)) {
        at(data.sectionSrcLine(4));
        return error.BadRef;
    }

    i = 0;
    while (i < t.cosmetic_count) : (i += 1) {
        const c = t.cosmetics[@intCast(usize, i)];
        const line = data.cosmeticSrcLine(i);
        if (c.name.len == 0 or c.name.len > def.MAX_NAME_LEN) {
            at(line);
            return error.DamagedLine;
        }
        if (c.unlock < 1 or c.unlock > 4) {
            at(line);
            return error.BadRef;
        }
        if (c.price <= 0) {
            at(line);
            return error.BadRef;
        }
    }

    // ---- upgrades (full 5×3 grid) -----------------------------------------
    if (t.upgrade_count < 0) {
        at(data.sectionSrcLine(3));
        return error.DamagedLine;
    }
    if (t.upgrade_count > 15) {
        at(data.sectionSrcLine(3));
        return error.Overflow;
    }
    if (t.upgrade_count != 15) {
        at(data.sectionSrcLine(3));
        return error.BadRef;
    }

    var seen: [15]i32 = undefined;
    k = 0;
    while (k < 15) : (k += 1) {
        seen[k] = 0;
    }

    i = 0;
    while (i < t.upgrade_count) : (i += 1) {
        const u = t.upgrades[@intCast(usize, i)];
        const line = data.upgradeSrcLine(i);
        if (u.axis < 0 or u.axis > 4) {
            at(line);
            return error.BadRef;
        }
        if (u.tier < 1 or u.tier > 3) {
            at(line);
            return error.BadRef;
        }
        const cell: i32 = u.axis * 3 + (u.tier - 1);
        if (seen[@intCast(usize, cell)] != 0) {
            at(line);
            return error.BadRef;
        }
        seen[@intCast(usize, cell)] = 1;

        var c: usize = 0;
        while (c < 3) : (c += 1) {
            const kind = u.cost[c].kind;
            if (kind < 0 or kind > COST_KIND_MAX) {
                at(line);
                return error.BadRef;
            }
        }
    }

    return;
}
