// pe_debug.zig — PE32 container reader for z9dbg (P3-M4, spec §15.2).
//
// Finds the linked `.debug_line` section and hands its bytes to the existing
// DWARF 2/3/4 interpreter (`dwarf_lines.openSections`), and turns the PE COFF
// symbol table into function entries. When the image has no DWARF line table
// but carries an IMAGE_DEBUG_TYPE_COFF blob (`/DEBUGTYPE:COFF`), it delegates
// to `coff_lines`. No PDB/CodeView and no DWARF 5.
//
// Rows and functions are link-time VAs. The session layer applies
// `imageBase_fn() - image_base` as the runtime bias.

const std = @import("std");
const file_mod = @import("std_file");
const dwarf = @import("dwarf_lines.zig");
const coff = @import("coff_lines.zig");

const IMAGE_FILE_MACHINE_I386: u16 = 0x014c;
const IMAGE_DEBUG_TYPE_COFF: u32 = 1;
const STORAGE_EXTERNAL: u8 = 2;
const STORAGE_STATIC: u8 = 3;

const Pe = struct {
    image_base: u32,
    sec_off: usize,
    sec_count: usize,
    symtab: usize,
    nsym: usize,
    strtab: usize,
    str_size: usize,
    dbg_off: usize,
    dbg_size: usize,
};

fn u16At(data: []const u8, off: usize) dwarf.DwarfError!u16 {
    if (off > data.len or data.len - off < 2) return error.Corrupt;
    var lo: u32 = @intCast(u32, data[off]);
    var hi: u32 = @intCast(u32, data[off + 1]);
    return @intCast(u16, lo | (hi << @intCast(u32, 8)));
}

fn i16At(data: []const u8, off: usize) dwarf.DwarfError!i16 {
    var v = try u16At(data, off);
    return @bitCast(i16, v);
}

fn u32At(data: []const u8, off: usize) dwarf.DwarfError!u32 {
    if (off > data.len or data.len - off < 4) return error.Corrupt;
    var b0: u32 = @intCast(u32, data[off]);
    var b1: u32 = @intCast(u32, data[off + 1]);
    var b2: u32 = @intCast(u32, data[off + 2]);
    var b3: u32 = @intCast(u32, data[off + 3]);
    return b0 | (b1 << @intCast(u32, 8)) | (b2 << @intCast(u32, 16)) | (b3 << @intCast(u32, 24));
}

fn parsePe(data: []const u8) dwarf.DwarfError!Pe {
    if (data.len < 0x40) return error.NotElf;
    if (data[0] != 'M' or data[1] != 'Z') return error.NotElf;
    var pe_off: usize = @intCast(usize, try u32At(data, 0x3c));
    if (pe_off > data.len or data.len - pe_off < 24) return error.NotElf;
    if (data[pe_off] != 'P' or data[pe_off + 1] != 'E' or
        data[pe_off + 2] != 0 or data[pe_off + 3] != 0) return error.NotElf;
    var coff_off = pe_off + 4;
    if ((try u16At(data, coff_off)) != IMAGE_FILE_MACHINE_I386) return error.NotElf;
    var sec_count: usize = @intCast(usize, try u16At(data, coff_off + 2));
    var symtab: usize = @intCast(usize, try u32At(data, coff_off + 8));
    var nsym: usize = @intCast(usize, try u32At(data, coff_off + 12));
    var opt_size: usize = @intCast(usize, try u16At(data, coff_off + 16));
    var opt = coff_off + 20;
    if (opt > data.len or data.len - opt < opt_size) return error.Corrupt;
    if (opt_size < 96) return error.Corrupt;
    if ((try u16At(data, opt)) != 0x010b) return error.Corrupt;
    var image_base = try u32At(data, opt + 28);
    var nrva = try u32At(data, opt + 92);
    var dbg_rva: u32 = 0;
    var dbg_size_u: u32 = 0;
    if (nrva > 6 and opt_size >= 96 + 7 * 8) {
        dbg_rva = try u32At(data, opt + 96 + 6 * 8);
        dbg_size_u = try u32At(data, opt + 96 + 6 * 8 + 4);
    }
    var sec_off = opt + opt_size;
    var strtab: usize = 0;
    var str_size: usize = 0;
    if (symtab != 0 and nsym != 0) {
        if (symtab > data.len or nsym > (data.len - symtab) / 18) return error.Corrupt;
        var st = symtab + nsym * 18;
        if (st > data.len or data.len - st < 4) return error.Corrupt;
        strtab = st;
        str_size = @intCast(usize, try u32At(data, st));
        if (str_size < 4 or strtab > data.len or data.len - strtab < str_size) return error.Corrupt;
    }
    var p = Pe{
        .image_base = image_base,
        .sec_off = sec_off,
        .sec_count = sec_count,
        .symtab = symtab,
        .nsym = nsym,
        .strtab = strtab,
        .str_size = str_size,
        .dbg_off = 0,
        .dbg_size = 0,
    };
    if (dbg_rva != 0 and dbg_size_u > 0) {
        var off = rvaToOff(data, &p, dbg_rva) orelse return error.Corrupt;
        var nentries = @intCast(usize, dbg_size_u) / 28;
        var i: usize = 0;
        while (i < nentries) : (i += 1) {
            var e = off + i * 28;
            if (e > data.len or data.len - e < 28) break;
            if ((try u32At(data, e + 12)) != IMAGE_DEBUG_TYPE_COFF) continue;
            var sz = @intCast(usize, try u32At(data, e + 16));
            var raw_ptr: usize = @intCast(usize, try u32At(data, e + 24));
            var raw_rva = try u32At(data, e + 20);
            var blob = raw_ptr;
            if (blob == 0) blob = rvaToOff(data, &p, raw_rva) orelse return error.Corrupt;
            if (blob > data.len or data.len - blob < sz) return error.Corrupt;
            p.dbg_off = blob;
            p.dbg_size = sz;
            return p;
        }
    }
    return p;
}

fn sectionAt(data: []const u8, p: *const Pe, idx: usize) ?usize {
    if (idx >= p.sec_count) return null;
    var off = p.sec_off + idx * 40;
    if (off > data.len or data.len - off < 40) return null;
    return off;
}

fn sectionVa(data: []const u8, p: *const Pe, idx: usize) ?u32 {
    var off = sectionAt(data, p, idx) orelse return null;
    return u32At(data, off + 12) catch null;
}

fn rvaToOff(data: []const u8, p: *const Pe, rva: u32) ?usize {
    var i: usize = 0;
    while (i < p.sec_count) : (i += 1) {
        var off = sectionAt(data, p, i) orelse return null;
        var vsize = u32At(data, off + 8) catch return null;
        var va = u32At(data, off + 12) catch return null;
        var raw_size = u32At(data, off + 16) catch return null;
        var raw_ptr = u32At(data, off + 20) catch return null;
        var span = vsize;
        if (raw_size > span) span = raw_size;
        if (rva < va) continue;
        var delta = rva - va;
        if (delta >= span) continue;
        return @intCast(usize, raw_ptr) + @intCast(usize, delta);
    }
    return null;
}

fn decimalAt(s: []const u8) usize {
    var v: usize = 0;
    var i: usize = 0;
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
        v = v * 10 + @intCast(usize, s[i] - '0');
    }
    return v;
}

fn sectionName(data: []const u8, p: *const Pe, sec_off: usize) []const u8 {
    if (sec_off + 8 > data.len) return "";
    if (data[sec_off] == '/') {
        if (p.strtab == 0) return "";
        var noff = decimalAt(data[sec_off + 1 .. sec_off + 8]);
        if (noff >= p.str_size) return "";
        var start = p.strtab + noff;
        var end = p.strtab + p.str_size;
        var i = start;
        while (i < end and i < data.len and data[i] != 0) : (i += 1) {}
        return data[start..i];
    }
    var n: usize = 0;
    while (n < 8 and data[sec_off + n] != 0) : (n += 1) {}
    return data[sec_off .. sec_off + n];
}

fn nameIs(s: []const u8, want: []const u8) bool {
    if (s.len == want.len) {
        var i: usize = 0;
        while (i < s.len) : (i += 1) {
            if (s[i] != want[i]) return false;
        }
        return true;
    }
    // PE images may truncate a section name to 8 bytes; accept the prefix when
    // the string table is unavailable.
    if (s.len != 8 or want.len < 8) return false;
    var j: usize = 0;
    while (j < 8) : (j += 1) {
        if (s[j] != want[j]) return false;
    }
    return true;
}

fn findSection(data: []const u8, p: *const Pe, want: []const u8) ?usize {
    var i: usize = 0;
    while (i < p.sec_count) : (i += 1) {
        var off = sectionAt(data, p, i) orelse return null;
        var nm = sectionName(data, p, off);
        if (nameIs(nm, want)) return off;
    }
    return null;
}

fn stripUnderscore(s: []const u8) []const u8 {
    if (s.len > 0 and s[0] == '_') return s[1..];
    return s;
}

fn symName(data: []const u8, p: *const Pe, off: usize) []const u8 {
    var zero = u32At(data, off) catch return "";
    if (zero == 0) {
        var noff = u32At(data, off + 4) catch return "";
        if (noff < 4 or @intCast(usize, noff) >= p.str_size) return "";
        var start = p.strtab + @intCast(usize, noff);
        var end = p.strtab + p.str_size;
        var i = start;
        while (i < end and i < data.len and data[i] != 0) : (i += 1) {}
        return data[start..i];
    }
    var i: usize = 0;
    while (i < 8 and off + i < data.len and data[off + i] != 0) : (i += 1) {}
    return data[off .. off + i];
}

fn collectFuncs(arena: *std.arena.Arena, data: []const u8, p: *const Pe) dwarf.DwarfError![]dwarf.Func {
    var cap = p.nsym;
    if (cap == 0) cap = 1;
    var raw = std.arena.alloc(arena, @sizeOf(dwarf.Func) * cap) catch return error.OutOfMemory;
    var funcs = @ptrCast([*]dwarf.Func, raw);
    if (p.nsym == 0 or p.symtab == 0) return funcs[0..0];
    var n: usize = 0;
    var i: usize = 0;
    while (i < p.nsym) {
        var off = p.symtab + i * 18;
        if (off > data.len or data.len - off < 18) break;
        var value = try u32At(data, off + 8);
        var snum = try i16At(data, off + 12);
        var typ = try u16At(data, off + 14);
        var cls = data[off + 16];
        var naux: usize = @intCast(usize, data[off + 17]);
        if (i + 1 + naux > p.nsym) break;
        if ((cls == STORAGE_EXTERNAL or cls == STORAGE_STATIC) and
            (typ & @intCast(u16, 0x20)) != 0 and snum > 0) {
            var sv = sectionVa(data, p, @intCast(usize, snum - 1));
            if (sv) |s| {
                var nm = stripUnderscore(symName(data, p, off));
                if (nm.len > 0 and n < p.nsym) {
                    var size: u32 = 0;
                    if (cls == STORAGE_EXTERNAL and naux >= 1 and (typ & @intCast(u16, 0x20)) != 0) {
                        size = u32At(data, off + 18 + 4) catch 0;
                    }
                    funcs[n] = dwarf.Func{
                        .addr = p.image_base +% s +% value,
                        .size = size,
                        .name = nm,
                    };
                    n += 1;
                }
            }
        }
        i += 1 + naux;
    }
    return funcs[0..n];
}

pub fn open(arena: *std.arena.Arena, exe: []const u8) dwarf.DwarfError!dwarf.DebugInfo {
    var data = file_mod.readAll(arena, exe) catch return error.OpenFailed;
    var p = try parsePe(data);
    if (p.image_base == 0) return error.Corrupt;
    var funcs = try collectFuncs(arena, data, &p);
    var line_off = findSection(data, &p, ".debug_line");
    if (line_off) |lo| {
        var vsize = try u32At(data, lo + 8);
        var raw_size = try u32At(data, lo + 16);
        var raw_ptr = @intCast(usize, try u32At(data, lo + 20));
        var size: usize = @intCast(usize, raw_size);
        if (vsize != 0 and @intCast(usize, vsize) < size) size = @intCast(usize, vsize);
        if (raw_ptr > data.len or data.len - raw_ptr < size) return error.Corrupt;
        var di = try dwarf.openSections(arena, data, data[raw_ptr .. raw_ptr + size], p.image_base);
        try dwarf.injectFuncs(&di, funcs);
        return di;
    }
    if (p.dbg_off != 0) {
        return coff.parseBlob(arena, data, p.dbg_off, p.dbg_size, p.image_base, p.sec_off, p.sec_count);
    }
    var empty: []const u8 = "";
    var di = try dwarf.openSections(arena, data, empty, p.image_base);
    try dwarf.injectFuncs(&di, funcs);
    return di;
}
