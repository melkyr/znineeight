// data_load.zig — UNDERSANDED data.z98 whole-file loader (spec §25.10).
//
// Drives the scanner (data_scan.zig), row parsers and rule packer
// (data_schema.zig), and the zero-row helpers (data_fallback.zig). All file
// bytes and [text] slices live in the caller's permanent arena.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const def = @import("def.zig");
const text_scan = @import("text_scan.zig");

const scan = @import("data_scan.zig");
const state = @import("data_state.zig");
const schema = @import("data_schema.zig");
const fallback = @import("data_fallback.zig");

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

fn beginTextEntry(content: []u8, t: *def.Tables, line: []const u8, pos: usize, eq: usize, line_no: i32, active: *bool, val_start: *usize, val_end: *usize) schema.LoadErr!void {
    if (active.*) {
        finishTextValue(content, t, val_start.*, val_end.*);
        active.* = false;
    }
    const key = text_scan.trimSpaces(line[0..eq]);
    if (key.len == 0 or !schema.textKeyKnown(key)) return schema.failLine(line_no);
    const tcount: usize = @intCast(usize, t.text_count);
    var ki: usize = 0;
    while (ki < tcount) : (ki += 1) {
        if (scan.eql(t.text_key[ki], key)) return schema.failLine(line_no);
    }
    if (tcount >= def.MAX_TEXT_KEYS) {
        state.err_line = line_no;
        return error.TooMany;
    }
    t.text_key[tcount] = key;
    val_start.* = pos + eq + 1;
    val_end.* = pos + line.len;
    active.* = true;
}

pub fn loadFile(arena: *arena_mod.Arena, path: []const u8, tables: *def.Tables) schema.LoadErr!void {
    tables.loaded = 0;
    state.err_line = 0;
    state.resetLines();
    const content = file_mod.readAll(arena, path) catch return error.Io;

    var tmp: def.Tables = undefined;
    fallback.clearTables(&tmp);

    var fields: [scan.ROW_MAX]scan.RowField = undefined;
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
        const line = text_scan.stripCR(content[pos..eol]);
        line_no += 1;

        const t = text_scan.trimSpaces(line);

        if (!header_ok) {
            if (t.len == 0 or t[0] == '#') {
                pos = if (eol < content.len) eol + 1 else content.len;
                continue;
            }
            if (scan.eql(line, "format=2")) {
                header_ok = true;
                tmp.content_version = 2;
                state.header_line = line_no;
            } else {
                return schema.failLine(line_no);
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
            if (t.len == 0) return schema.failLine(line_no);
            if (t[0] != '[') {
                const ei = equalsIndex(line);
                if (ei < 0) return schema.failLine(line_no);
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
                if (line.len > 1 and line[1] == ' ') return schema.failLine(line_no);
                return schema.failLine(line_no);
            }
            if (t[0] != '[') {
                const ei = equalsIndex(line);
                if (ei < 0) return schema.failLine(line_no);
                try beginTextEntry(content, &tmp, line, pos, @intCast(usize, ei), line_no, &text_active, &text_val_start, &text_val_end);
                pos = if (eol < content.len) eol + 1 else content.len;
                continue;
            }
        }

        const cls = scan.classifyLine(line);
        if (cls == 1) {
            return schema.failLine(line_no);
        } else if (cls == 2) {
            if (text_active) {
                finishTextValue(content, &tmp, text_val_start, text_val_end);
                text_active = false;
            }
            const name = t[1 .. t.len - 1];
            const sid = scan.sectionId(name);
            if (sid < 0) return schema.failLine(line_no);
            section = sid;
            state.section_line[@intCast(usize, sid)] = line_no;
            if (sid == 7) text_section_line = line_no;
        } else if (cls == 3) {
            if (section < 0 or section == 7) return schema.failLine(line_no);
            if (!scan.parseRowKV(line, &fields, &fn_count)) return schema.failLine(line_no);

            if (section == 0) {
                if (@intCast(usize, tmp.def_count) >= def.MAX_CREATURES) {
                    state.err_line = line_no;
                    return error.Overflow;
                }
                var d = fallback.zeroDef();
                try schema.parseCreature(fields[0..], fn_count, line_no, &d);
                tmp.defs[@intCast(usize, tmp.def_count)] = d;
                state.def_src[@intCast(usize, tmp.def_count)] = line_no;
                tmp.def_count += 1;
            } else if (section == 1) {
                if (rule_n >= def.MAX_RULES) {
                    state.err_line = line_no;
                    return error.Overflow;
                }
                try schema.parseRule(fields[0..], fn_count, line_no, &rule_owner[rule_n], &rule_row[rule_n]);
                rule_in_line[rule_n] = line_no;
                rule_n += 1;
            } else if (section == 2) {
                if (tool_n >= def.MAX_TOOLS) {
                    state.err_line = line_no;
                    return error.Overflow;
                }
                var tr = fallback.zeroTool();
                try schema.parseTool(fields[0..], fn_count, line_no, &tr);
                tmp.tools[tool_n] = tr;
                state.tool_src[tool_n] = line_no;
                tool_n += 1;
            } else if (section == 3) {
                if (upgrade_n >= 15) {
                    state.err_line = line_no;
                    return error.Overflow;
                }
                var ur = fallback.zeroUpgrade();
                try schema.parseUpgrade(fields[0..], fn_count, line_no, &ur);
                tmp.upgrades[upgrade_n] = ur;
                state.upgrade_src[upgrade_n] = line_no;
                upgrade_n += 1;
            } else if (section == 4) {
                if (cosmetic_n >= def.MAX_COSMETICS) {
                    state.err_line = line_no;
                    return error.Overflow;
                }
                var cr = def.CosmeticRow{ .name = "", .price = 0, .unlock = 0 };
                try schema.parseCosmetic(fields[0..], fn_count, line_no, &cr);
                tmp.cosmetics[cosmetic_n] = cr;
                state.cosmetic_src[cosmetic_n] = line_no;
                cosmetic_n += 1;
            } else if (section == 5) {
                try schema.parseEncounter(fields[0..], fn_count, line_no, &tmp);
            } else if (section == 6) {
                try schema.parseZone(fields[0..], fn_count, line_no, &tmp);
            } else {
                return schema.failLine(line_no);
            }
        } else {
            return schema.failLine(line_no);
        }

        pos = if (eol < content.len) eol + 1 else content.len;
    }
    state.last_line = line_no;

    if (!header_ok) {
        state.err_line = 1;
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
        state.err_line = if (text_section_line > 0) text_section_line else 1;
        return error.Overflow;
    }

    try schema.packRules(&tmp, &rule_owner, &rule_row, &rule_in_line, rule_n);

    tmp.loaded = 1;
    state.lines_ready = true;
    tables.* = tmp;
    return;
}
