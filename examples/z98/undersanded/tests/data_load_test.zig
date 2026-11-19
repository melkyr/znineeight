// data_load_test.zig — native Linux tests for the M6 data.z98 loader, fallback
// builder, override accessors, and field-by-field dump (spec §25.10).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/data_load_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/data_load_test"
//   "$OUT/data_load_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const buf_mod = @import("std_buf");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const data = @import("../data.zig");
const creatures = @import("../creatures_t1.zig");
const tables = @import("../tables_t1.zig");

const DATA_PATH = "examples/z98/undersanded/data.z98";
const GOLDEN_PATH = "examples/z98/undersanded/tests/fixtures/defs_golden.txt";
const TMP_OVERRIDE = "/tmp/m6t3_override.z98";
const TMP_BAD = "/tmp/m6t3_bad.z98";
const TMP_UNKNOWN_SECTION = "/tmp/m6t3_unknown_section.z98";
const TMP_UNKNOWN_KEY = "/tmp/m6t3_unknown_key.z98";
const TMP_BAD_HEADER = "/tmp/m6t3_bad_header.z98";
const TMP_TEXT = "/tmp/m6t3_text_paragraphs.z98";
const TMP_TEXT_CRLF = "/tmp/m6t3_text_crlf.z98";
const TMP_TEXT_TWO_SPACE = "/tmp/m6t3_text_two_space.z98";
const TMP_TEXT_DUP = "/tmp/m6t3_text_duplicate.z98";
const TMP_RULE_BADREF = "/tmp/m6t3_rule_badref.z98";

var fails: usize = 0;
var arena_buf: [256 * 1024]u8 = undefined;
var arena: arena_mod.Arena = undefined;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn resetArena() void {
    arena = arena_mod.init(arena_buf[0..]);
}

fn bytesEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn contains(a: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (a.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= a.len) : (i += 1) {
        if (bytesEq(a[i .. i + needle.len], needle)) return true;
    }
    return false;
}

fn textFind(t: *const def.Tables, key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < @intCast(usize, t.text_count)) : (i += 1) {
        if (bytesEq(t.text_key[i], key)) return t.text_val[i];
    }
    return null;
}

fn dropEq(a: def.DropLine, b: def.DropLine) bool {
    return a.part == b.part and a.count == b.count;
}

fn dropTableEq(a: []const def.DropLine, b: []const def.DropLine) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (!dropEq(a[i], b[i])) return false;
    }
    return true;
}

fn defEq(a: def.CreatureDef, b: def.CreatureDef) bool {
    if (a.id != b.id) return false;
    if (a.name_len != b.name_len) return false;
    var i: usize = 0;
    while (i < def.MAX_NAME_LEN) : (i += 1) {
        if (a.name[i] != b.name[i]) return false;
    }
    if (a.family != b.family) return false;
    if (a.role != b.role) return false;
    if (a.zone_mask != b.zone_mask) return false;
    if (a.phase_mask != b.phase_mask) return false;
    if (a.hp != b.hp) return false;
    if (a.resolve != b.resolve) return false;
    if (a.speed != b.speed) return false;
    if (a.attack != b.attack) return false;
    if (a.thrash_regen != b.thrash_regen) return false;
    if (a.despair_regen != b.despair_regen) return false;
    if (a.armor_pct != b.armor_pct) return false;
    if (a.flags != b.flags) return false;
    if (a.resist_restrain_pct != b.resist_restrain_pct) return false;
    if (a.blind_chance != b.blind_chance) return false;
    if (a.subdue_chance != b.subdue_chance) return false;
    if (a.discharge_stat != b.discharge_stat) return false;
    if (a.discharge_th != b.discharge_th) return false;
    if (a.discharge_dmg != b.discharge_dmg) return false;
    if (a.armor_below_th != b.armor_below_th) return false;
    if (a.armor_below_pct != b.armor_below_pct) return false;
    if (a.speed_below_stat != b.speed_below_stat) return false;
    if (a.speed_below_th != b.speed_below_th) return false;
    if (a.speed_below_add != b.speed_below_add) return false;
    if (a.atk_below_th != b.atk_below_th) return false;
    if (a.atk_below_pct != b.atk_below_pct) return false;
    if (a.flee_kind != b.flee_kind) return false;
    if (a.flee_th != b.flee_th) return false;
    if (a.grudge_family != b.grudge_family) return false;
    if (a.grudge_kind != b.grudge_kind) return false;
    if (a.grudge_value != b.grudge_value) return false;
    if (!dropTableEq(a.sub[0..], b.sub[0..])) return false;
    if (!dropTableEq(a.kill[0..], b.kill[0..])) return false;
    if (!dropTableEq(a.over[0..], b.over[0..])) return false;
    if (a.sale != b.sale) return false;
    if (a.respawn[0] != b.respawn[0]) return false;
    if (a.respawn[1] != b.respawn[1]) return false;
    if (a.respawn[2] != b.respawn[2]) return false;
    if (a.counter_tool != b.counter_tool) return false;
    if (a.rule_start != b.rule_start) return false;
    if (a.rule_count != b.rule_count) return false;
    return true;
}

fn ruleEq(a: def.Rule, b: def.Rule) bool {
    return a.cond_op == b.cond_op and a.cond_a == b.cond_a and a.cond_b == b.cond_b and
        a.effect_op == b.effect_op and a.effect_a == b.effect_a and a.effect_b == b.effect_b and
        a.timing == b.timing;
}

fn costEq(a: def.CostSlot, b: def.CostSlot) bool {
    return a.kind == b.kind and a.amt == b.amt;
}

fn toolEq(a: def.ToolRow, b: def.ToolRow) bool {
    if (a.id != b.id or a.kind != b.kind) return false;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (!costEq(a.cost[i], b.cost[i])) return false;
    }
    return true;
}

fn upgradeEq(a: def.UpgradeRow, b: def.UpgradeRow) bool {
    if (a.axis != b.axis or a.tier != b.tier) return false;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (!costEq(a.cost[i], b.cost[i])) return false;
    }
    return true;
}

fn cosmeticEq(a: def.CosmeticRow, b: def.CosmeticRow) bool {
    return bytesEq(a.name, b.name) and a.price == b.price and a.unlock == b.unlock;
}

fn encounterEq(a: def.EncounterRow, b: def.EncounterRow) bool {
    return a.def_index == b.def_index and a.weight == b.weight;
}

fn tablesMatch(a: *const def.Tables, b: *const def.Tables) bool {
    if (a.content_version != b.content_version) return false;
    if (a.def_count != b.def_count) return false;
    if (a.rule_count != b.rule_count) return false;
    if (a.tool_count != b.tool_count) return false;
    if (a.upgrade_count != b.upgrade_count) return false;
    if (a.cosmetic_count != b.cosmetic_count) return false;

    var i: usize = 0;
    while (i < @intCast(usize, a.def_count)) : (i += 1) {
        if (!defEq(a.defs[i], b.defs[i])) return false;
    }
    i = 0;
    while (i < @intCast(usize, a.rule_count)) : (i += 1) {
        if (!ruleEq(a.rules[i], b.rules[i])) return false;
    }
    i = 0;
    while (i < @intCast(usize, a.tool_count)) : (i += 1) {
        if (!toolEq(a.tools[i], b.tools[i])) return false;
    }
    i = 0;
    while (i < @intCast(usize, a.upgrade_count)) : (i += 1) {
        if (!upgradeEq(a.upgrades[i], b.upgrades[i])) return false;
    }
    i = 0;
    while (i < @intCast(usize, a.cosmetic_count)) : (i += 1) {
        if (!cosmeticEq(a.cosmetics[i], b.cosmetics[i])) return false;
    }
    i = 0;
    while (i < def.MAX_ZONES * 2) : (i += 1) {
        if (a.enc_count[i] != b.enc_count[i]) return false;
        const base: usize = @intCast(usize, i) * def.MAX_ENCOUNTER;
        var j: usize = 0;
        while (j < @intCast(usize, a.enc_count[i])) : (j += 1) {
            if (!encounterEq(a.encounters[base + j], b.encounters[base + j])) return false;
        }
    }
    i = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        if (a.zone_cost[i] != b.zone_cost[i]) return false;
        if (a.zone_boss[i] != b.zone_boss[i]) return false;
    }
    return true;
}

fn tLoadMatchesFallback() bool {
    data.uninstall();
    resetArena();
    var fb: def.Tables = undefined;
    data.buildFallback(&fb);
    var loaded: def.Tables = undefined;
    data.loadFile(&arena, DATA_PATH, &loaded) catch return false;

    if (fb.text_count != 0) return false;
    if (loaded.text_count != 1) return false;
    if (!bytesEq(loaded.text_key[0], "manual.1")) return false;

    var text_bytes: usize = 0;
    var ti: usize = 0;
    while (ti < @intCast(usize, loaded.text_count)) : (ti += 1) {
        if (loaded.text_val[ti].len == 0) return false;
        text_bytes += loaded.text_val[ti].len;
    }
    if (loaded.text_count > @intCast(i32, def.MAX_TEXT_KEYS)) return false;
    if (text_bytes > def.MAX_TEXT_BYTES) return false;
    if (!contains(loaded.text_val[0], "\n\n")) return false;

    return tablesMatch(&loaded, &fb);
}

fn tTextParagraphs() bool {
    data.uninstall();
    resetArena();
    const text = "format=2\n[text]\nmanual.1=First paragraph.\n \n #Hash prose retained.\nmanual.2=Second entry.\n";
    file_mod.writeAll(TMP_TEXT, text) catch return false;

    var t: def.Tables = undefined;
    data.loadFile(&arena, TMP_TEXT, &t) catch return false;
    if (t.text_count != 2) return false;

    const p1 = textFind(&t, "manual.1") orelse return false;
    const p2 = textFind(&t, "manual.2") orelse return false;
    if (!bytesEq(p1, "First paragraph.\n\n#Hash prose retained.")) return false;
    if (!bytesEq(p2, "Second entry.")) return false;
    return true;
}

fn tTextCrlf() bool {
    data.uninstall();
    resetArena();
    const text = "format=2\r\n[text]\r\nmanual.1=abc\r\n def\r\n";
    file_mod.writeAll(TMP_TEXT_CRLF, text) catch return false;

    var t: def.Tables = undefined;
    data.loadFile(&arena, TMP_TEXT_CRLF, &t) catch return false;
    if (t.text_count != 1) return false;
    const p = textFind(&t, "manual.1") orelse return false;
    if (!bytesEq(p, "abc\ndef")) return false;
    if (contains(p, "\r")) return false;
    return true;
}

fn tTextTwoSpaceContinuation() bool {
    data.uninstall();
    resetArena();
    const text = "format=2\n[text]\nmanual.1=First\n  two spaces\n";
    file_mod.writeAll(TMP_TEXT_TWO_SPACE, text) catch return false;

    var t: def.Tables = undefined;
    data.loadFile(&arena, TMP_TEXT_TWO_SPACE, &t) catch return false;
    if (t.text_count != 1) return false;
    const p = textFind(&t, "manual.1") orelse return false;
    return bytesEq(p, "First\n two spaces");
}

fn tTextDuplicateKey() bool {
    file_mod.writeAll(TMP_TEXT_DUP, "format=2\n[text]\nmanual.1=One.\nmanual.1=Two.\n") catch return false;
    return loadFailsWith(TMP_TEXT_DUP, 4);
}

fn tRuleBadRefLine() bool {
    data.uninstall();
    resetArena();
    const text = "format=2\n[rules]\nowner=999,cond_op=1,cond_a=1,cond_b=0,effect_op=3,effect_a=1,effect_b=0,timing=0\n[text]\nmanual.1=x\n";
    file_mod.writeAll(TMP_RULE_BADREF, text) catch return false;

    var t: def.Tables = undefined;
    data.buildFallback(&t);
    var failed = false;
    var badref = false;
    data.loadFile(&arena, TMP_RULE_BADREF, &t) catch |e| {
        failed = true;
        badref = (e == error.BadRef);
    };
    if (!failed or !badref) return false;
    return data.err_line == 3;
}

fn tDumpGolden() bool {
    data.uninstall();
    resetArena();
    var loaded: def.Tables = undefined;
    data.loadFile(&arena, DATA_PATH, &loaded) catch return false;

    var b1 = buf_mod.initCapacity(&arena, 64 * 1024) catch return false;
    data.dumpDefs(&loaded, &b1);
    const got1 = buf_mod.slice(&b1);

    var b2 = buf_mod.initCapacity(&arena, 64 * 1024) catch return false;
    data.dumpDefs(&loaded, &b2);
    const got2 = buf_mod.slice(&b2);
    if (!bytesEq(got1, got2)) return false;

    const want = file_mod.readAll(&arena, GOLDEN_PATH) catch return false;
    return bytesEq(got1, want);
}

fn loadFailsWith(path: []const u8, line: i32) bool {
    data.uninstall();
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    var failed = false;
    var damaged = false;
    data.loadFile(&arena, path, &t) catch |e| {
        failed = true;
        damaged = (e == error.DamagedLine);
    };
    if (!failed or !damaged) return false;
    return data.err_line == line;
}

fn tRejectUnknownSection() bool {
    file_mod.writeAll(TMP_UNKNOWN_SECTION, "format=2\n[bogus]\n") catch return false;
    return loadFailsWith(TMP_UNKNOWN_SECTION, 2);
}

fn tRejectUnknownKey() bool {
    file_mod.writeAll(TMP_UNKNOWN_KEY, "format=2\n[creatures]\nbogus=1\n") catch return false;
    return loadFailsWith(TMP_UNKNOWN_KEY, 3);
}

fn tRejectHeader() bool {
    file_mod.writeAll(TMP_BAD_HEADER, "format=1\n") catch return false;
    return loadFailsWith(TMP_BAD_HEADER, 1);
}

fn tBadFieldLeavesTables() bool {
    data.uninstall();
    resetArena();
    var t: def.Tables = undefined;
    data.buildFallback(&t);
    const before_hp = t.defs[0].hp;
    const before_sale = t.defs[1].sale;
    const before_rules = t.rule_count;
    const before_tools = t.tool_count;

    file_mod.writeAll(TMP_BAD, "format=2\n[creatures]\nid=1,name=Mystic Eel,family=1,role=1,zone_mask=3,phase_mask=3,hp=abc,resolve=80,speed=10,attack=6,thrash_regen=0,despair_regen=8,armor_pct=100,flags=0,resist_restrain_pct=100,blind_chance=0,subdue_chance=95,discharge_stat=0,discharge_th=0,discharge_dmg=0,armor_below_th=0,armor_below_pct=0,speed_below_stat=0,speed_below_th=0,speed_below_add=0,atk_below_th=0,atk_below_pct=0,flee_kind=0,flee_th=0,grudge_family=0,grudge_kind=0,grudge_value=0,sale=20,respawn_sub=3,respawn_kill=9,respawn_over=15,counter_tool=0\n") catch return false;

    var failed = false;
    var damaged = false;
    data.loadFile(&arena, TMP_BAD, &t) catch |e| {
        failed = true;
        damaged = (e == error.DamagedLine);
    };
    if (!failed or !damaged) return false;
    if (data.err_line != 3) return false;
    if (t.defs[0].hp != before_hp) return false;
    if (t.defs[1].sale != before_sale) return false;
    if (t.rule_count != before_rules) return false;
    if (t.tool_count != before_tools) return false;
    return true;
}

fn tOverrideLifecycle() bool {
    data.uninstall();
    resetArena();

    const text = "format=2\n[creatures]\nid=1,name=Mystic Eel,family=1,role=1,zone_mask=3,phase_mask=3,hp=71,resolve=80,speed=10,attack=6,thrash_regen=0,despair_regen=8,armor_pct=100,flags=0,resist_restrain_pct=100,blind_chance=0,subdue_chance=95,discharge_stat=0,discharge_th=0,discharge_dmg=0,armor_below_th=0,armor_below_pct=0,speed_below_stat=0,speed_below_th=0,speed_below_add=0,atk_below_th=0,atk_below_pct=0,flee_kind=0,flee_th=0,grudge_family=0,grudge_kind=0,grudge_value=0,sale=21,respawn_sub=3,respawn_kill=9,respawn_over=15,counter_tool=0\n[encounter]\nzone=0,phase=0,def_index=0,weight=31\n[text]\nmanual.1=Changed.\n";
    file_mod.writeAll(TMP_OVERRIDE, text) catch return false;

    if (creatures.defCount() != 18) return false;
    if (creatures.defAt(0).hp != 70) return false;
    const fb_rows = tables.rows(0, 0);
    if (fb_rows.len != 5) return false;
    if (fb_rows[0].weight != 30) return false;

    var t: def.Tables = undefined;
    data.loadFile(&arena, TMP_OVERRIDE, &t) catch return false;
    data.install(&t);

    if (creatures.defCount() != 1) return false;
    if (creatures.defAt(0).hp != 71) return false;
    if (creatures.defAt(0).sale != 21) return false;
    const ov_rows = tables.rows(0, 0);
    if (ov_rows.len != 1) return false;
    if (ov_rows[0].weight != 31) return false;

    data.uninstall();
    if (creatures.defCount() != 18) return false;
    if (creatures.defAt(0).hp != 70) return false;
    const back = tables.rows(0, 0);
    if (back.len != 5) return false;
    if (back[0].weight != 30) return false;
    return true;
}

pub fn main() void {
    report("load_data_matches_fallback", tLoadMatchesFallback());
    report("text_paragraphs_and_hash_prose", tTextParagraphs());
    report("text_crlf_strips_cr", tTextCrlf());
    report("text_two_space_continuation", tTextTwoSpaceContinuation());
    report("text_duplicate_key_rejected", tTextDuplicateKey());
    report("rule_badref_records_line", tRuleBadRefLine());
    report("dump_defs_golden_byte_exact", tDumpGolden());
    report("reject_unknown_section_line", tRejectUnknownSection());
    report("reject_unknown_key_line", tRejectUnknownKey());
    report("reject_non_format2_header_line", tRejectHeader());
    report("bad_field_leaves_tables_untouched", tBadFieldLeavesTables());
    report("override_visible_only_after_install", tOverrideLifecycle());

    data.uninstall();
    if (fails != 0) os.exit(1);
    io.write("data_load_test PASS\n");
}
