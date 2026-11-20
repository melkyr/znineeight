// data.zig — UNDERSANDED data.z98 public hub (spec §25.10).
//
// The stateless scanner lives in data_scan.zig and the loader/fallback/dump in
// data_load.zig. This module keeps the historical public names so callers and
// tests do not need import churn. Mutable probe state is forwarded through
// wrapper functions; the public err_line copy is refreshed by loadFile.

const def = @import("def.zig");
const scan = @import("data_scan.zig");
const load = @import("data_load.zig");
const arena_mod = @import("std_arena.zig");
const buf_mod = @import("std_buf.zig");

pub const MAX_LINE: usize = scan.MAX_LINE;
pub const ROW_MAX: usize = scan.ROW_MAX;
pub const RowField = scan.RowField;
pub const LoadErr = load.LoadErr;

// BSS Tables image owned by the data layer; the game/startup loads into this
// and installs it (§35).
pub var g_tables: def.Tables = undefined;

// Last DamagedLine/BadRef/Overflow/TooMany line (0 = none). validate writes
// this value; loadFile refreshes it from the loader on completion.
pub var err_line: i32 = 0;

pub fn parseI32(s: []const u8) ?i32 {
    return scan.parseI32(s);
}

pub fn sectionId(name: []const u8) i32 {
    return scan.sectionId(name);
}

pub fn classifyLine(line: []const u8) i32 {
    return scan.classifyLine(line);
}

pub fn parseRowKV(line: []const u8, out: *[ROW_MAX]RowField, n: *usize) bool {
    return scan.parseRowKV(line, out, n);
}

pub fn resetLines() void {
    load.resetLines();
}

pub fn headerSrcLine() i32 {
    return load.headerSrcLine();
}

pub fn lastSrcLine() i32 {
    return load.lastSrcLine();
}

pub fn sectionSrcLine(sid: i32) i32 {
    return load.sectionSrcLine(sid);
}

pub fn defSrcLine(i: i32) i32 {
    return load.defSrcLine(i);
}

pub fn ruleSrcLine(i: i32) i32 {
    return load.ruleSrcLine(i);
}

pub fn toolSrcLine(i: i32) i32 {
    return load.toolSrcLine(i);
}

pub fn upgradeSrcLine(i: i32) i32 {
    return load.upgradeSrcLine(i);
}

pub fn cosmeticSrcLine(i: i32) i32 {
    return load.cosmeticSrcLine(i);
}

pub fn encSrcLine(i: i32) i32 {
    return load.encSrcLine(i);
}

pub fn zoneSrcLine(i: i32) i32 {
    return load.zoneSrcLine(i);
}

pub fn install(t: *def.Tables) void {
    load.install(t);
}

pub fn uninstall() void {
    load.uninstall();
}

pub fn buildFallback(out: *def.Tables) void {
    load.buildFallback(out);
}

pub fn textKeyKnown(k: []const u8) bool {
    return load.textKeyKnown(k);
}

pub fn textFind(key: []const u8) ?[]const u8 {
    return load.textFind(key);
}

pub fn textFindIn(t: *const def.Tables, key: []const u8) ?[]const u8 {
    return load.textFindIn(t, key);
}

pub fn loadFile(arena: *arena_mod.Arena, path: []const u8, tables: *def.Tables) LoadErr!void {
    load.loadFile(arena, path, tables) catch |e| {
        err_line = load.err_line;
        return e;
    };
    err_line = load.err_line;
}

pub fn dumpDefs(t: *const def.Tables, out: *buf_mod.Buf) void {
    load.dumpDefs(t, out);
}
