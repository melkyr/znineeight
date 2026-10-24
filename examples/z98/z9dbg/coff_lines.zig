// coff_lines.zig — embedded COFF symbol + line-number reader (P3-M4, spec §15.1).
//
// Consumes the IMAGE_DEBUG_TYPE_COFF (1) blob that MSVC 6 emits for
// `cl /Z7` + `link /DEBUG /DEBUGTYPE:COFF`. The two Lva* header fields are
// offsets from the start of the debug-data blob (not RVAs). FILE symbols
// (storage class 103, aux format 4) name the current source file; a STATIC
// section-definition symbol's aux carries that group's line-record count; a
// line record with Linenumber == 0 is a function header and is skipped.
// Function/row addresses are link-time VAs: ImageBase + section.VirtualAddress
// + Value (the session layer applies the runtime bias).
//
// No PDB, no CodeView. The common dwarf_lines.DebugInfo is produced here so the
// session layer does not know which era toolchain produced the debug info.

const std = @import("std");
const dwarf = @import("dwarf_lines.zig");

const IMAGE_FILE_MACHINE_I386: u16 = 0x014c;
const IMAGE_DEBUG_TYPE_COFF: u32 = 1;

const STORAGE_EXTERNAL: u8 = 2;
const STORAGE_STATIC: u8 = 3;
const STORAGE_FILE: u8 = 103;

const Pe = struct {
    image_base: u32,
    sec_off: usize,
    sec_count: usize,
    symtab: usize,
    nsym: usize,
    strtab: usize,
    str_size: usize,
    debug_off: usize,
    debug_size: usize,
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
    var coff = pe_off + 4;
    var machine = try u16At(data, coff);
    if (machine != IMAGE_FILE_MACHINE_I386) return error.NotElf;
    var sec_count: usize = @intCast(usize, try u16At(data, coff + 2));
    var symtab: usize = @intCast(usize, try u32At(data, coff + 8));
    var nsym: usize = @intCast(usize, try u32At(data, coff + 12));
    var opt_size: usize = @intCast(usize, try u16At(data, coff + 16));
    var opt = coff + 20;
    if (opt > data.len or data.len - opt < opt_size) return error.Corrupt;
    if (opt_size < 96) return error.Corrupt;
    var magic = try u16At(data, opt);
    if (magic != 0x010b) return error.Corrupt;
    var image_base = try u32At(data, opt + 28);
    var nrva = try u32At(data, opt + 92);
    var dbg_rva: u32 = 0;
    var dbg_size: u32 = 0;
    if (nrva > 6 and opt_size >= 96 + 7 * 8) {
        dbg_rva = try u32At(data, opt + 96 + 6 * 8);
        dbg_size = try u32At(data, opt + 96 + 6 * 8 + 4);
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
        .debug_off = 0,
        .debug_size = 0,
    };
    if (dbg_rva != 0 and dbg_size > 0) {
        var off = rvaToOff(data, &p, dbg_rva) orelse return error.Corrupt;
        var nentries = @intCast(usize, dbg_size) / 28;
        var i: usize = 0;
        while (i < nentries) : (i += 1) {
            var e = off + i * 28;
            if (e > data.len or data.len - e < 28) break;
            var typ = try u32At(data, e + 12);
            if (typ != IMAGE_DEBUG_TYPE_COFF) continue;
            var sz = @intCast(usize, try u32At(data, e + 16));
            var raw_ptr: usize = @intCast(usize, try u32At(data, e + 24));
            var raw_rva = try u32At(data, e + 20);
            var blob = raw_ptr;
            if (blob == 0) blob = rvaToOff(data, &p, raw_rva) orelse return error.Corrupt;
            if (blob > data.len or data.len - blob < sz) return error.Corrupt;
            p.debug_off = blob;
            p.debug_size = sz;
            return p;
        }
    }
    return error.Corrupt;
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

fn stripUnderscore(s: []const u8) []const u8 {
    if (s.len > 0 and s[0] == '_') return s[1..];
    return s;
}

fn addFileName(arena: *std.arena.Arena, files: [*][]const u8, n: *usize, raw: []const u8) dwarf.DwarfError!void {
    var tmp: [1024]u8 = undefined;
    var norm = dwarf.normalizePath(tmp[0..], raw);
    if (norm.len == 0) return;
    var mem = std.arena.alloc(arena, norm.len) catch return error.OutOfMemory;
    var dst = @ptrCast([*]u8, mem);
    var i: usize = 0;
    while (i < norm.len) : (i += 1) dst[i] = norm[i];
    files[n.*] = dst[0..norm.len];
    n.* += 1;
}

// Pure blob entry (unit tests and the PE driver share it).
pub fn parseBlob(arena: *std.arena.Arena, data: []const u8, blob_off: usize, blob_len: usize, image_base: u32, sec_off: usize, sec_count: usize) dwarf.DwarfError!dwarf.DebugInfo {
    if (blob_off > data.len or data.len - blob_off < 16) return error.Corrupt;
    if (blob_len < 16 or blob_off > data.len or data.len - blob_off < blob_len) return error.Corrupt;
    var end = blob_off + blob_len;
    var nsym: usize = @intCast(usize, try u32At(data, blob_off));
    var lva_sym: usize = @intCast(usize, try u32At(data, blob_off + 4));
    var nline: usize = @intCast(usize, try u32At(data, blob_off + 8));
    var lva_line: usize = @intCast(usize, try u32At(data, blob_off + 12));
    if (lva_sym > blob_len or lva_line > blob_len) return error.Corrupt;
    var sym_start = blob_off + lva_sym;
    var line_start = blob_off + lva_line;
    if (sym_start > end or nsym > (end - sym_start) / 18) return error.Corrupt;
    var line_cap = nline;
    if (line_start > end) return error.Corrupt;
    var avail = (end - line_start) / 6;
    if (line_cap > avail) line_cap = avail;

    // The COFF string table follows the symbol records (u32 size including
    // itself). Long names store a zero first dword and a string-table offset
    // in the second. If the table is absent/truncated, leave it empty.
    var sym_end = sym_start + nsym * 18;
    var strtab: usize = 0;
    var str_size: usize = 0;
    if (sym_end <= end and end - sym_end >= 4) {
        var ssz: usize = @intCast(usize, try u32At(data, sym_end));
        if (ssz >= 4 and sym_end <= end and end - sym_end >= ssz) {
            strtab = sym_end;
            str_size = ssz;
        }
    }

    var pe = Pe{
        .image_base = image_base,
        .sec_off = sec_off,
        .sec_count = sec_count,
        .symtab = 0,
        .nsym = 0,
        .strtab = strtab,
        .str_size = str_size,
        .debug_off = blob_off,
        .debug_size = blob_len,
    };

    var row_cap = line_cap;
    if (row_cap == 0) row_cap = 1;
    var rows_mem = std.arena.alloc(arena, @sizeOf(dwarf.Row) * row_cap) catch return error.OutOfMemory;
    var rows = @ptrCast([*]dwarf.Row, rows_mem);
    var row_n: usize = 0;

    var file_cap = nsym;
    if (file_cap == 0) file_cap = 1;
    var files_mem = std.arena.alloc(arena, @sizeOf([]const u8) * file_cap) catch return error.OutOfMemory;
    var files = @ptrCast([*][]const u8, files_mem);
    var file_n: usize = 0;

    var func_cap = nsym;
    if (func_cap == 0) func_cap = 1;
    var funcs_mem = std.arena.alloc(arena, @sizeOf(dwarf.Func) * func_cap) catch return error.OutOfMemory;
    var funcs = @ptrCast([*]dwarf.Func, funcs_mem);
    var func_n: usize = 0;

    var file_idx: u32 = 0xFFFFFFFF;
    var line_cursor = line_start;
    var i: usize = 0;
    while (i < nsym) {
        var off = sym_start + i * 18;
        if (off > end or end - off < 18) return error.Corrupt;
        var value = try u32At(data, off + 8);
        var snum = try i16At(data, off + 12);
        var typ = try u16At(data, off + 14);
        var cls = data[off + 16];
        var naux: usize = @intCast(usize, data[off + 17]);
        if (i + 1 + naux > nsym) return error.Corrupt;
        if (cls == STORAGE_FILE and naux >= 1) {
            var aux = off + 18;
            var flen: usize = 0;
            while (flen < 18 and data[aux + flen] != 0) : (flen += 1) {}
            try addFileName(arena, files, &file_n, data[aux .. aux + flen]);
            if (file_n > 0) file_idx = @intCast(u32, file_n - 1);
        } else if (cls == STORAGE_STATIC and typ == 0 and snum > 0 and naux >= 1) {
            // Section definition: its aux carries the line-record count.
            var aux = off + 18;
            var nlnno: usize = @intCast(try u16At(data, aux + 6));
            var k: usize = 0;
            while (k < nlnno) : (k += 1) {
                if (line_cursor > end or end - line_cursor < 6) return error.Corrupt;
                var va = try u32At(data, line_cursor);
                var ln = try u16At(data, line_cursor + 4);
                line_cursor += 6;
                if (ln == 0) continue;
                if (row_n >= row_cap) return error.Corrupt;
                // §15.1: a line record's VirtualAddress is the code RVA.
                rows[row_n] = dwarf.Row{
                    .addr = image_base +% va,
                    .line = @intCast(u32, ln),
                    .file = file_idx,
                    .end = false,
                };
                row_n += 1;
            }
        } else if ((cls == STORAGE_EXTERNAL or cls == STORAGE_STATIC) and
            (typ & @intCast(u16, 0x20)) != 0 and snum > 0) {
            var secva = sectionVa(data, &pe, @intCast(usize, snum - 1));
            if (secva) |sv| {
                var nm = stripUnderscore(symName(data, &pe, off));
                if (nm.len > 0 and func_n < func_cap) {
                    var size: u32 = 0;
                    if (cls == STORAGE_EXTERNAL and naux >= 1 and (typ & @intCast(u16, 0x20)) != 0) {
                        size = u32At(data, off + 18 + 4) catch 0;
                    }
                    funcs[func_n] = dwarf.Func{
                        .addr = image_base +% sv +% value,
                        .size = size,
                        .name = nm,
                    };
                    func_n += 1;
                }
            }
        }
        i += 1 + naux;
    }
    return dwarf.buildInfo(arena, data, image_base, rows[0..row_n], files[0..file_n], funcs[0..func_n]);
}

// Self-contained entry for a synthetic or real PE image: locate the Type-1
// debug-directory entry and parse its blob.
pub fn openBytes(arena: *std.arena.Arena, data: []const u8, image_base_hint: u32) dwarf.DwarfError!dwarf.DebugInfo {
    var p = try parsePe(data);
    var image_base = p.image_base;
    if (image_base == 0) image_base = image_base_hint;
    if (p.debug_off == 0) return error.Corrupt;
    return parseBlob(arena, data, p.debug_off, p.debug_size, image_base, p.sec_off, p.sec_count);
}
