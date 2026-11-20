// data_state.zig — UNDERSANDED data.z98 source-line probes and override hook.
//
// Populated by data_load.loadFile; read by validate.zig through the data.zig
// public hub. Fallback/synthetic images leave lines_ready false and report
// line 0. The install/uninstall pair owns the static content override.

const def = @import("def.zig");

pub var err_line: i32 = 0;

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
