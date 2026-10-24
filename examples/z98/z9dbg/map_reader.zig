// map_reader.zig — reader for the three compiler-emitted `.z98dbg.*` files.
//
// Byte layout is owned by sf/src/debug_map.zig (P3-M1). This reader is
// file-backed and sectioned (spec §5 / plan R4): open reads only the 20-byte
// headers and the `.lines` group headers; a group's runs are read on demand,
// and `.syms` / `.cnames` contents are loaded only when first queried. It
// never retains the whole `.lines` run stream.
//
// `.syms` is sorted by (src_file, src_line, name); `.cnames` by src_name.
// `.lines` is grouped per output file in emission order, with runs sorted by
// out_line_start. Forward queries match the map `src_file` by exact path,
// path suffix, or basename; reverse queries do the same for `out_file`.
//
// `.cnames` is optional (spec §7.2): a missing file means no C names, not an
// error. Its header/records are still validated when the file is present.

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
    runs_off: u32,
    run_count: u32,
};

const Run = struct {
    src_line: u32,
    out_start: u32,
    out_count: u32,
};

const Header = struct {
    count: u32,
    size: usize,
};

pub const MapReader = struct {
    arena: *std.arena.Arena,
    syms_file: file_mod.File,
    lines_file: file_mod.File,
    cnames_file: file_mod.File,
    has_cnames: bool,
    syms_size: usize,
    lines_size: usize,
    cnames_size: usize,
    sym_count: usize,
    line_run_count: usize,
    cname_count: usize,
    syms_loaded: bool,
    syms: []const u8,
    sym_offs: [*]u32,
    groups: [*]Group,
    group_len: usize,
    group_cap: usize,
    cnames_loaded: bool,
    cnames: []const u8,
    cname_offs: [*]u32,
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

fn readExact(f: *file_mod.File, buf: []u8) MapError!void {
    var got: usize = 0;
    while (got < buf.len) {
        var n = file_mod.read(f, buf[got..]) catch return error.OpenFailed;
        if (n == 0) return error.Corrupt;
        got += n;
    }
}

fn readAt(f: *file_mod.File, off: usize, buf: []u8) MapError!void {
    _ = file_mod.seek(f, @intCast(i64, off), file_mod.SeekWhence.Set) catch return error.OpenFailed;
    try readExact(f, buf);
}

fn readU16AtFile(f: *file_mod.File, off: usize) MapError!u16 {
    var b: [2]u8 = undefined;
    try readAt(f, off, b[0..]);
    var lo: u32 = @intCast(u32, b[0]);
    var hi: u32 = @intCast(u32, b[1]);
    return @intCast(u16, lo | (hi << @intCast(u32, 8)));
}

fn readU32AtFile(f: *file_mod.File, off: usize) MapError!u32 {
    var b: [4]u8 = undefined;
    try readAt(f, off, b[0..]);
    var b0: u32 = @intCast(u32, b[0]);
    var b1: u32 = @intCast(u32, b[1]);
    var b2: u32 = @intCast(u32, b[2]);
    var b3: u32 = @intCast(u32, b[3]);
    return b0 | (b1 << @intCast(u32, 8)) | (b2 << @intCast(u32, 16)) | (b3 << @intCast(u32, 24));
}

fn readStr16Alloc(arena: *std.arena.Arena, f: *file_mod.File, off: usize, limit: usize, next: *usize) MapError![]const u8 {
    var n = try readU16AtFile(f, off);
    var len = @intCast(usize, n);
    var start = off + 2;
    if (start > limit or limit - start < len) return error.Corrupt;
    next.* = start + len;
    if (len == 0) {
        var empty: []const u8 = "";
        return empty;
    }
    var raw = std.arena.alloc(arena, len) catch return error.OutOfMemory;
    try readAt(f, start, raw[0..len]);
    return raw[0..len];
}

fn skipStr16(f: *file_mod.File, off: usize, limit: usize, next: *usize) MapError!void {
    var n = try readU16AtFile(f, off);
    var len = @intCast(usize, n);
    var start = off + 2;
    if (start > limit or limit - start < len) return error.Corrupt;
    next.* = start + len;
}

fn readHeader(f: *file_mod.File, magic: []const u8) MapError!Header {
    var size_i = file_mod.size(f) catch return error.OpenFailed;
    if (size_i < @intCast(i64, 0) or size_i > @intCast(i64, 4294967295)) return error.Corrupt;
    var size = @intCast(usize, size_i);
    if (size < HEADER_LEN) return error.Corrupt;
    var hdr: [HEADER_LEN]u8 = undefined;
    try readAt(f, 0, hdr[0..]);
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        if (hdr[i] != magic[i]) return error.Corrupt;
    }
    var ver = try readU32At(hdr[0..], 8);
    if (ver != 1) return error.UnsupportedVersion;
    var total = try readU32At(hdr[0..], 16);
    if (@intCast(usize, total) != size) return error.Corrupt;
    return Header{ .count = try readU32At(hdr[0..], 12), .size = size };
}

fn validateSyms(f: *file_mod.File, size: usize, count: u32) MapError!void {
    var n = @intCast(usize, count);
    if (size < HEADER_LEN or n > (size - HEADER_LEN) / 11) return error.Corrupt;
    var off: usize = HEADER_LEN;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (off > size or size - off < 5) return error.Corrupt;
        var head: [5]u8 = undefined;
        try readAt(f, off, head[0..]);
        if (head[0] > 1) return error.Corrupt;
        off += 5;
        var next: usize = 0;
        try skipStr16(f, off, size, &next);
        off = next;
        try skipStr16(f, off, size, &next);
        off = next;
        try skipStr16(f, off, size, &next);
        off = next;
    }
    if (off != size) return error.Corrupt;
}

fn validateCnames(f: *file_mod.File, size: usize, count: u32) MapError!void {
    var n = @intCast(usize, count);
    if (size < HEADER_LEN or n > (size - HEADER_LEN) / 4) return error.Corrupt;
    var off: usize = HEADER_LEN;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var next: usize = 0;
        try skipStr16(f, off, size, &next);
        off = next;
        try skipStr16(f, off, size, &next);
        off = next;
    }
    if (off != size) return error.Corrupt;
}

fn allocU32(arena: *std.arena.Arena, count: usize) MapError![*]u32 {
    if (count == 0) return @ptrCast([*]u32, @intToPtr(*u8, 0));
    var raw = std.arena.alloc(arena, @intCast(usize, @sizeOf(u32)) * count) catch return error.OutOfMemory;
    return @ptrCast([*]u32, raw);
}

fn parseSyms(arena: *std.arena.Arena, data: []const u8, count: u32) MapError![*]u32 {
    var n = @intCast(usize, count);
    if (data.len < HEADER_LEN) return error.Corrupt;
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

fn groupsEnsure(self: *MapReader, need: usize) MapError!void {
    if (need <= self.group_cap) return;
    var cap = self.group_cap;
    if (cap == 0) cap = 8;
    while (cap < need) : (cap *= 2) {}
    var raw = std.arena.alloc(self.arena, @intCast(usize, @sizeOf(Group)) * cap) catch return error.OutOfMemory;
    var dst = @ptrCast([*]Group, raw);
    var i: usize = 0;
    while (i < self.group_len) : (i += 1) {
        dst[i] = self.groups[i];
    }
    self.groups = dst;
    self.group_cap = cap;
}

fn buildGroups(self: *MapReader, expected_runs: u32) MapError!void {
    var off: usize = HEADER_LEN;
    var total: usize = 0;
    while (off < self.lines_size) {
        try groupsEnsure(self, self.group_len + 1);
        var next: usize = 0;
        var sf = try readStr16Alloc(self.arena, &self.lines_file, off, self.lines_size, &next);
        off = next;
        var of = try readStr16Alloc(self.arena, &self.lines_file, off, self.lines_size, &next);
        off = next;
        var rc = try readU32AtFile(&self.lines_file, off);
        off += 4;
        var run_n = @intCast(usize, rc);
        if (off > self.lines_size or run_n > (self.lines_size - off) / 12) return error.Corrupt;
        if (off > 4294967295) return error.Corrupt;
        self.groups[self.group_len] = Group{
            .src_file = sf,
            .out_file = of,
            .runs_off = @intCast(u32, off),
            .run_count = rc,
        };
        self.group_len += 1;
        off += run_n * 12;
        total += run_n;
    }
    if (off != self.lines_size) return error.Corrupt;
    if (total != @intCast(usize, expected_runs)) return error.Corrupt;
}

fn readWhole(self: *MapReader, f: *file_mod.File, size: usize) MapError![]u8 {
    var raw = std.arena.alloc(self.arena, size) catch return error.OutOfMemory;
    if (size > 0) try readAt(f, 0, raw[0..size]);
    return raw[0..size];
}

fn loadSyms(self: *MapReader) bool {
    if (self.syms_loaded) return true;
    var data = readWhole(self, &self.syms_file, self.syms_size) catch return false;
    var offs = parseSyms(self.arena, data, @intCast(u32, self.sym_count)) catch return false;
    self.syms = data;
    self.sym_offs = offs;
    self.syms_loaded = true;
    return true;
}

fn loadCnames(self: *MapReader) bool {
    if (!self.has_cnames) return false;
    if (self.cnames_loaded) return true;
    var data = readWhole(self, &self.cnames_file, self.cnames_size) catch return false;
    var offs = parseCnames(self.arena, data, @intCast(u32, self.cname_count)) catch return false;
    self.cnames = data;
    self.cname_offs = offs;
    self.cnames_loaded = true;
    return true;
}

fn readRun(self: *MapReader, g: Group, idx: usize) ?Run {
    var off = @intCast(usize, g.runs_off) + idx * 12;
    var b: [12]u8 = undefined;
    readAt(&self.lines_file, off, b[0..]) catch return null;
    return Run{
        .src_line = readU32At(b[0..], 0) catch return null,
        .out_start = readU32At(b[0..], 4) catch return null,
        .out_count = readU32At(b[0..], 8) catch return null,
    };
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

fn nullFile(arena: *std.arena.Arena) file_mod.File {
    return file_mod.File{
        .handle = @intToPtr(*void, 0),
        .size_cache = @intCast(i64, -1),
        .arena = arena,
    };
}

pub fn open(arena: *std.arena.Arena, prefix: []const u8) MapError!MapReader {
    var syms_path = try appendPath(arena, prefix, ".z98dbg.syms");
    var lines_path = try appendPath(arena, prefix, ".z98dbg.lines");
    var cnames_path = try appendPath(arena, prefix, ".z98dbg.cnames");
    var syms_file = file_mod.open(arena, syms_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var lines_file = file_mod.open(arena, lines_path, file_mod.Mode.Read) catch return error.OpenFailed;
    var has_cnames = file_mod.exists(cnames_path);
    var cnames_file = nullFile(arena);
    if (has_cnames) {
        cnames_file = file_mod.open(arena, cnames_path, file_mod.Mode.Read) catch return error.OpenFailed;
    }

    var msyms: []const u8 = "Z98DBGsy";
    var mlines: []const u8 = "Z98DBGln";
    var mcnames: []const u8 = "Z98DBGcn";
    var sym_hdr = try readHeader(&syms_file, msyms);
    var line_hdr = try readHeader(&lines_file, mlines);
    var cname_hdr = Header{ .count = 0, .size = 0 };
    if (has_cnames) {
        cname_hdr = try readHeader(&cnames_file, mcnames);
    }

    try validateSyms(&syms_file, sym_hdr.size, sym_hdr.count);
    if (has_cnames) try validateCnames(&cnames_file, cname_hdr.size, cname_hdr.count);

    var empty: []const u8 = "";
    var r = MapReader{
        .arena = arena,
        .syms_file = syms_file,
        .lines_file = lines_file,
        .cnames_file = cnames_file,
        .has_cnames = has_cnames,
        .syms_size = sym_hdr.size,
        .lines_size = line_hdr.size,
        .cnames_size = cname_hdr.size,
        .sym_count = @intCast(usize, sym_hdr.count),
        .line_run_count = @intCast(usize, line_hdr.count),
        .cname_count = @intCast(usize, cname_hdr.count),
        .syms_loaded = false,
        .syms = empty,
        .sym_offs = undefined,
        .groups = undefined,
        .group_len = 0,
        .group_cap = 0,
        .cnames_loaded = false,
        .cnames = empty,
        .cname_offs = undefined,
    };
    try buildGroups(&r, line_hdr.count);
    return r;
}

pub fn symbolCount(self: *MapReader) usize {
    return self.sym_count;
}

pub fn groupCount(self: *MapReader) usize {
    return self.group_len;
}

pub fn lineRunCount(self: *MapReader) usize {
    return self.line_run_count;
}

pub fn cnameCount(self: *MapReader) usize {
    if (!self.has_cnames) return 0;
    return self.cname_count;
}

pub fn symbolByIndex(self: *MapReader, idx: usize) ?Symbol {
    if (idx >= self.sym_count) return null;
    if (!loadSyms(self)) return null;
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
    if (best_score < 3 and loadSyms(self)) {
        i = 0;
        while (i < self.sym_count) : (i += 1) {
            var sym = symbolByIndex(self, i) orelse continue;
            var s2 = fileScore(sym.src_file, query);
            if (s2 > best_score) {
                best_score = s2;
                best = sym.src_file;
            }
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
    if (!loadSyms(self)) return null;
    var best: ?Symbol = null;
    var best_line: u32 = 0;
    var i: usize = 0;
    while (i < self.sym_count) : (i += 1) {
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
    if (!loadSyms(self)) return null;
    var i: usize = 0;
    while (i < self.sym_count) : (i += 1) {
        var sym = symbolByIndex(self, i) orelse continue;
        if (sym.kind != 0) continue;
        if (std.str.eql(sym.src_name, name)) return sym;
    }
    return null;
}

pub fn cnameFor(self: *MapReader, src_name: []const u8) ?[]const u8 {
    if (!loadCnames(self)) return null;
    var i: usize = 0;
    while (i < self.cname_count) : (i += 1) {
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
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var r = readRun(self, g, j) orelse return null;
            if (r.src_line == line) {
                return LineRow{ .src_file = g.src_file, .out_file = g.out_file, .src_line = r.src_line, .out_line = r.out_start };
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
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var r = readRun(self, g, j) orelse return null;
            if (r.src_line >= after) {
                if (!found or r.src_line < best) {
                    best = r.src_line;
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
        var j: usize = 0;
        while (j < @intCast(usize, g.run_count)) : (j += 1) {
            var r = readRun(self, g, j) orelse return count;
            if (r.src_line == line) {
                if (count < out.len) {
                    out[count] = LineRow{ .src_file = g.src_file, .out_file = g.out_file, .src_line = r.src_line, .out_line = r.out_start };
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
        var lo: usize = 0;
        var hi: usize = @intCast(usize, g.run_count);
        while (lo < hi) {
            var mid = lo + (hi - lo) / 2;
            var r = readRun(self, g, mid) orelse return null;
            if (out_line < r.out_start) {
                hi = mid;
            } else if (out_line - r.out_start >= r.out_count) {
                lo = mid + 1;
            } else {
                return LineRow{ .src_file = g.src_file, .out_file = g.out_file, .src_line = r.src_line, .out_line = out_line };
            }
        }
    }
    return null;
}
