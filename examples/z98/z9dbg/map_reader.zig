// map_reader.zig — reader for the three compiler-emitted `.z98dbg.*` files.
//
// Byte layout is owned by sf/src/debug_map.zig (P3-M1); this module validates
// and indexes it without trusting its counts. Files are loaded once into the
// caller's arena; records are decoded lazily from their stored offsets, and
// every string is a zero-copy slice into the loaded bytes. Corrupt or
// truncated input returns a MapError (never traps).
//
// `.syms` is sorted by (src_file, src_line, name); `.cnames` by src_name.
// `.lines` is grouped per output file in emission order, with runs sorted by
// out_line_start. Forward queries match the map `src_file` by exact path,
// path suffix, or basename; reverse queries do the same for `out_file`.

const std = @import("std");
const file_mod = @import("std_file");

const HEADER_LEN: usize = 20;

pub const MapError = error{ OpenFailed, Corrupt, UnsupportedVersion, OutOfMemory };

pub const Symbol = struct {
    kind: u8,
    src_line: u32,
    src_name: []const u8,
    module_stem: []const u8,
    src_file: []const u8,
};

pub const LineRow = struct {
    src_file: []const u8,
    out_file: []const u8,
    src_line: u32,
    out_line: u32,
};

const Group = struct {
    src_file: []const u8,
    out_file: []const u8,
    runs_off: usize,
    run_count: u32,
};

const ParsedLines = struct {
    groups: [*]Group,
    group_len: usize,
    run_len: usize,
};

pub const MapReader = struct {
    syms: []const u8,
    lines: []const u8,
    cnames: []const u8,
    sym_offs: [*]u32,
    sym_len: usize,
    groups: [*]Group,
    group_len: usize,
    run_len: usize,
    cname_offs: [*]u32,
    cname_len: usize,
};

fn readU16At(data: []const u8, off: usize) MapError!u16 {
    if (off > data.len or data.len - off < 2) return error.Corrupt;
    var lo: u32 = @intCast(u32, data[off]);
    var hi: u32 = @intCast(u32, data[off + 1]);
    return @intCast(u16, lo | (hi << @intCast(u32, 8)));
}

fn readU32At(data: []const u8, off: usize) MapError!u32 {
    if (off > data.len or data.len - off < 4) return error.Corrupt;
    var b0: u32 = @intCast(u32, data[off]);
    var b1: u32 = @intCast(u32, data[off + 1]);
    var b2: u32 = @intCast(u32, data[off + 2]);
    var b3: u32 = @intCast(u32, data[off + 3]);
    return b0 | (b1 << @intCast(u32, 8)) | (b2 << @intCast(u32, 16)) | (b3 << @intCast(u32, 24));
}

fn readStr16(data: []const u8, off: usize, next: *usize) MapError![]const u8 {
    var n = try readU16At(data, off);
    var start = off + 2;
    var len = @intCast(usize, n);
    if (start > data.len or data.len - start < len) return error.Corrupt;
    next.* = start + len;
    return data[start .. start + len];
}

fn checkMagic(data: []const u8, magic: []const u8) MapError!void {
    if (data.len < HEADER_LEN) return error.Corrupt;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (data[i] != magic[i]) return error.Corrupt;
    }
}

fn headerCount(data: []const u8) MapError!u32 {
    if (data.len < HEADER_LEN) return error.Corrupt;
    var ver = try readU32At(data, 8);
    if (ver != 1) return error.UnsupportedVersion;
    var total = try readU32At(data, 16);
    if (@intCast(usize, total) != data.len) return error.Corrupt;
    return try readU32At(data, 12);
}

fn allocU32(arena: *std.arena.Arena, count: usize) MapError![*]u32 {
    if (count == 0) return @ptrCast([*]u32, @intToPtr(*u8, 0));
    var raw = std.arena.alloc(arena, @intCast(usize, @sizeOf(u32)) * count) catch return error.OutOfMemory;
    return @ptrCast([*]u32, raw);
}

fn parseSyms(arena: *std.arena.Arena, data: []const u8, count: u32) MapError![*]u32 {
    var n = @intCast(usize, count);
    if (data.len < HEADER_LEN) return error.Corrupt;
    // Smallest record: u8 kind + u32 line + three empty str16s.
    if (n > (data.len - HEADER_LEN) / 11) return error.Corrupt;
    var offs = try allocU32(arena, n);
    var off: usize = HEADER_LEN;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (off >= data.len) return error.Corrupt;
        offs[i] = @intCast(u32, off);
        var kind = data[off];
        if (kind > 1) return error.Corrupt;
        off += 1;
        _ = try readU32At(data, off);
        off += 4;
        var next: usize = 0;
        _ = try readStr16(data, off, &next);
        off = next;
        _ = try readStr16(data, off, &next);
        off = next;
        _ = try readStr16(data, off, &next);
        off = next;
    }
    if (off != data.len) return error.Corrupt;
    return offs;
}

fn parseCnames(arena: *std.arena.Arena, data: []const u8, count: u32) MapError![*]u32 {
    var n = @intCast(usize, count);
    if (data.len < HEADER_LEN) return error.Corrupt;
    if (n > (data.len - HEADER_LEN) / 4) return error.Corrupt;
    var offs = try allocU32(arena, n);
    var off: usize = HEADER_LEN;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        offs[i] = @intCast(u32, off);
        var next: usize = 0;
        _ = try readStr16(data, off, &next);
        off = next;
        _ = try readStr16(data, off, &next);
        off = next;
    }
    if (off != data.len) return error.Corrupt;
    return offs;
}

fn countLineGroups(data: []const u8) MapError!usize {
    var off: usize = HEADER_LEN;
    var count: usize = 0;
    while (off < data.len) {
        var next: usize = 0;
        _ = try readStr16(data, off, &next);
        off = next;
        _ = try readStr16(data, off, &next);
        off = next;
        var rc = try readU32At(data, off);
        off += 4;
        var run_n = @intCast(usize, rc);
        if (off > data.len or run_n > (data.len - off) / 12) return error.Corrupt;
        off += run_n * 12;
        count += 1;
    }
    if (off != data.len) return error.Corrupt;
    return count;
}

fn parseLines(arena: *std.arena.Arena, data: []const u8, expected_runs: u32) MapError!ParsedLines {
    if (data.len < HEADER_LEN) return error.Corrupt;
    var group_count = try countLineGroups(data);
    var groups: [*]Group = undefined;
    if (group_count > 0) {
        var raw = std.arena.alloc(arena, @intCast(usize, @sizeOf(Group)) * group_count) catch return error.OutOfMemory;
        groups = @ptrCast([*]Group, raw);
    }
    var off: usize = HEADER_LEN;
    var gi: usize = 0;
    var total_runs: usize = 0;
    while (off < data.len) {
        var next: usize = 0;
        var sf = try readStr16(data, off, &next);
        off = next;
        var of = try readStr16(data, off, &next);
        off = next;
        var rc = try readU32At(data, off);
        off += 4;
        var runs_off = off;
        var run_n = @intCast(usize, rc);
        if (ioverflow(runs_off, run_n)) return error.Corrupt;
        if (runs_off > data.len or run_n > (data.len - runs_off) / 12) return error.Corrupt;
        var j: usize = 0;
        var prev_start: u32 = 0;
        var prev_end: u32 = 0;
        while (j < run_n) : (j += 1) {
            var sl = try readU32At(data, off);
            var st = try readU32At(data, off + 4);
            var ct = try readU32At(data, off + 8);
            off += 12;
            if (sl == 0 or ct == 0) return error.Corrupt;
            if (st > 4294967295 - ct) return error.Corrupt;
            if (j > 0) {
                if (st <= prev_start or st < prev_end) return error.Corrupt;
            }
            prev_start = st;
            prev_end = st + ct;
        }
        groups[gi] = Group{ .src_file = sf, .out_file = of, .runs_off = runs_off, .run_count = rc };
        gi += 1;
        total_runs += run_n;
    }
    if (off != data.len) return error.Corrupt;
    if (total_runs != @intCast(usize, expected_runs)) return error.Corrupt;
    return ParsedLines{ .groups = groups, .group_len = gi, .run_len = total_runs };
}

fn ioverflow(a: usize, b: usize) bool {
    return a > 4294967295 - b;
}

fn basename(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') return path[i + 1 ..];
    }
    return path;
}

fn isPathSuffix(path: []const u8, query: []const u8) bool {
    if (query.len >= path.len) return false;
    var start = path.len - query.len;
    if (!std.str.eql(path[start..], query)) return false;
    if (start == 0) return true;
    return path[start - 1] == '/';
}

fn fileScore(path: []const u8, query: []const u8) u8 {
    if (std.str.eql(path, query)) return 3;
    if (isPathSuffix(path, query)) return 2;
    if (std.str.eql(basename(path), basename(query))) return 1;
    return 0;
}

fn appendPath(arena: *std.arena.Arena, prefix: []const u8, suffix: []const u8) MapError![]u8 {
    var total = prefix.len + suffix.len;
    var raw = std.arena.alloc(arena, total) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) raw[i] = prefix[i];
    var j: usize = 0;
    while (j < suffix.len) : (j += 1) raw[prefix.len + j] = suffix[j];
    return raw[0..total];
}

pub fn open(arena: *std.arena.Arena, prefix: []const u8) MapError!MapReader {
    var syms_path = try appendPath(arena, prefix, ".z98dbg.syms");
    var lines_path = try appendPath(arena, prefix, ".z98dbg.lines");
    var cnames_path = try appendPath(arena, prefix, ".z98dbg.cnames");
    var syms = file_mod.readAll(arena, syms_path) catch return error.OpenFailed;
    var lines = file_mod.readAll(arena, lines_path) catch return error.OpenFailed;
    var cnames = file_mod.readAll(arena, cnames_path) catch return error.OpenFailed;

    var msyms: []const u8 = "Z98DBGsy";
    var mlines: []const u8 = "Z98DBGln";
    var mcnames: []const u8 = "Z98DBGcn";
    try checkMagic(syms, msyms);
    try checkMagic(lines, mlines);
    try checkMagic(cnames, mcnames);

    var sym_count = try headerCount(syms);
    var line_runs = try headerCount(lines);
    var cname_count = try headerCount(cnames);

    var sym_offs = try parseSyms(arena, syms, sym_count);
    var parsed_lines = try parseLines(arena, lines, line_runs);
    var cname_offs = try parseCnames(arena, cnames, cname_count);

    return MapReader{
        .syms = syms,
        .lines = lines,
        .cnames = cnames,
        .sym_offs = sym_offs,
        .sym_len = @intCast(usize, sym_count),
        .groups = parsed_lines.groups,
        .group_len = parsed_lines.group_len,
        .run_len = parsed_lines.run_len,
        .cname_offs = cname_offs,
        .cname_len = @intCast(usize, cname_count),
    };
}

pub fn symbolCount(self: *MapReader) usize {
    return self.sym_len;
}

pub fn groupCount(self: *MapReader) usize {
    return self.group_len;
}

pub fn lineRunCount(self: *MapReader) usize {
    return self.run_len;
}

pub fn cnameCount(self: *MapReader) usize {
    return self.cname_len;
}

pub fn symbolByIndex(self: *MapReader, idx: usize) ?Symbol {
    if (idx >= self.sym_len) return null;
    var off = @intCast(usize, self.sym_offs[idx]);
    if (off >= self.syms.len) return null;
    var kind = self.syms[off];
    var line = readU32At(self.syms, off + 1) catch return null;
    var next: usize = 0;
    var name = readStr16(self.syms, off + 5, &next) catch return null;
    var mod = readStr16(self.syms, next, &next) catch return null;
    var sf = readStr16(self.syms, next, &next) catch return null;
    return Symbol{ .kind = kind, .src_line = line, .src_name = name, .module_stem = mod, .src_file = sf };
}

pub fn resolveFile(self: *MapReader, query: []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_score: u8 = 0;
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        var s = fileScore(self.groups[i].src_file, query);
        if (s > best_score) {
            best_score = s;
            best = self.groups[i].src_file;
        }
    }
    i = 0;
    while (i < self.sym_len) : (i += 1) {
        var sym = symbolByIndex(self, i) orelse continue;
        var s2 = fileScore(sym.src_file, query);
        if (s2 > best_score) {
            best_score = s2;
            best = sym.src_file;
        }
    }
    return best;
}

pub fn resolveOutFile(self: *MapReader, query: []const u8) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_score: u8 = 0;
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        var s = fileScore(self.groups[i].out_file, query);
        if (s > best_score) {
            best_score = s;
            best = self.groups[i].out_file;
        }
    }
    return best;
}

pub fn symbolAt(self: *MapReader, file_query: []const u8, line: u32) ?Symbol {
    var file = resolveFile(self, file_query) orelse return null;
    var best: ?Symbol = null;
    var best_line: u32 = 0;
    var i: usize = 0;
    while (i < self.sym_len) : (i += 1) {
        var sym = symbolByIndex(self, i) orelse continue;
        if (sym.kind != 0) continue;
        if (!std.str.eql(sym.src_file, file)) continue;
        if (sym.src_line > line) continue;
        if (best == null or sym.src_line > best_line) {
            best = sym;
            best_line = sym.src_line;
        }
    }
    return best;
}

pub fn functionByName(self: *MapReader, name: []const u8) ?Symbol {
    var i: usize = 0;
    while (i < self.sym_len) : (i += 1) {
        var sym = symbolByIndex(self, i) orelse continue;
        if (sym.kind != 0) continue;
        if (std.str.eql(sym.src_name, name)) return sym;
    }
    return null;
}

pub fn cnameFor(self: *MapReader, src_name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < self.cname_len) : (i += 1) {
        var off = @intCast(usize, self.cname_offs[i]);
        var next: usize = 0;
        var name = readStr16(self.cnames, off, &next) catch continue;
        var mangled = readStr16(self.cnames, next, &next) catch continue;
        if (std.str.eql(name, src_name)) return mangled;
    }
    return null;
}

pub fn lineAt(self: *MapReader, file_query: []const u8, line: u32) ?LineRow {
    var file = resolveFile(self, file_query) orelse return null;
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        var g = self.groups[i];
        if (!std.str.eql(g.src_file, file)) continue;
        var off = g.runs_off;
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var sl = readU32At(self.lines, off) catch return null;
            var st = readU32At(self.lines, off + 4) catch return null;
            off += 12;
            if (sl == line) {
                return LineRow{ .src_file = g.src_file, .out_file = g.out_file, .src_line = sl, .out_line = st };
            }
        }
    }
    return null;
}

pub fn nextMappedLine(self: *MapReader, file_query: []const u8, after: u32) ?u32 {
    var file = resolveFile(self, file_query) orelse return null;
    var best: u32 = 0;
    var found = false;
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        var g = self.groups[i];
        if (!std.str.eql(g.src_file, file)) continue;
        var off = g.runs_off;
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var sl = readU32At(self.lines, off) catch return null;
            off += 12;
            if (sl >= after) {
                if (!found or sl < best) {
                    best = sl;
                    found = true;
                }
            }
        }
    }
    if (!found) return null;
    return best;
}

pub fn lineRowsAt(self: *MapReader, file_query: []const u8, line: u32, out: []LineRow) usize {
    var file = resolveFile(self, file_query) orelse return 0;
    var count: usize = 0;
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        var g = self.groups[i];
        if (!std.str.eql(g.src_file, file)) continue;
        var off = g.runs_off;
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var sl = readU32At(self.lines, off) catch return count;
            var st = readU32At(self.lines, off + 4) catch return count;
            off += 12;
            if (sl == line) {
                if (count < out.len) {
                    out[count] = LineRow{ .src_file = g.src_file, .out_file = g.out_file, .src_line = sl, .out_line = st };
                }
                count += 1;
            }
        }
    }
    return count;
}

pub fn reverseRowAt(self: *MapReader, out_query: []const u8, out_line: u32) ?LineRow {
    var out_file = resolveOutFile(self, out_query) orelse return null;
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        var g = self.groups[i];
        if (!std.str.eql(g.out_file, out_file)) continue;
        var off = g.runs_off;
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var sl = readU32At(self.lines, off) catch return null;
            var st = readU32At(self.lines, off + 4) catch return null;
            var ct = readU32At(self.lines, off + 8) catch return null;
            off += 12;
            if (out_line >= st and out_line < st + ct) {
                return LineRow{ .src_file = g.src_file, .out_file = g.out_file, .src_line = sl, .out_line = out_line };
            }
        }
    }
    return null;
}
