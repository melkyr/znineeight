// dwarf_lines.zig — in-z9dbg DWARF 2/3/4 .debug_line + ELF32 .symtab reader
// (P3-M3, spec §7.6).
//
// No helper binaries and no gdb: the debuggee's own ELF file is loaded into the
// caller arena, the line-number program is interpreted here, and function
// entries come from the linked symbol table. DWARF 5 (and DWARF64) units are
// skipped: v1 supports DWARF 2/3/4 only (CI pins -gdwarf-2).
//
// Address model: row.addr and Func.addr are link-time values. For a PIE
// (ET_DYN) the runtime load bias is read from /proc/<pid>/maps after exec and
// added/subtracted at the public boundary; ET_EXEC has bias 0.
//
// Frame-pointer unwinding is the caller's job; this module only resolves
// machine addresses to C file/line and C symbols.

const std = @import("std");
const file_mod = @import("std_file");

pub const DwarfError = error{ OpenFailed, Corrupt, OutOfMemory, NotElf };

const MAX_ROWS: usize = 262144;

pub const Row = struct {
    addr: u32,
    line: u32,
    file: u32,
    end: bool,
};

pub const Func = struct {
    addr: u32,
    size: u32,
    name: []const u8,
};

pub const DebugInfo = struct {
    arena: *std.arena.Arena,
    data: []const u8,
    base: u32,
    e_type: u16,
    rows: [*]Row,
    row_n: usize,
    files: [*][]const u8,
    file_n: usize,
    funcs: [*]Func,
    func_n: usize,
    has_line: bool,
    // A .debug_line unit used DWARF 5 or DWARF64 (both out of v1 scope).
    unsupported_version: bool,
    // ET_DYN executable whose runtime load bias could not be found in
    // /proc/<pid>/maps (renamed/symlinked exe); row/func addresses stay
    // link-time and the caller must warn.
    bias_unknown: bool,
};

const Parser = struct {
    arena: *std.arena.Arena,
    data: []const u8,
    rows: [*]Row,
    row_n: usize,
    row_cap: usize,
    files: [*][]const u8,
    file_n: usize,
    file_cap: usize,
    funcs: [*]Func,
    func_n: usize,
    func_cap: usize,
    unsupported: bool,
};

const Section = struct {
    name_off: u32,
    sh_type: u32,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_entsize: u32,
};

const LState = struct {
    addr: u32,
    file: u32,
    line: i64,
    is_stmt: bool,
    op_index: u32,
};

fn u8At(data: []const u8, off: usize) DwarfError!u8 {
    if (off >= data.len) return error.Corrupt;
    return data[off];
}

fn u16At(data: []const u8, off: usize) DwarfError!u16 {
    if (off > data.len or data.len - off < 2) return error.Corrupt;
    var lo: u32 = @intCast(u32, data[off]);
    var hi: u32 = @intCast(u32, data[off + 1]);
    return @intCast(u16, lo | (hi << @intCast(u32, 8)));
}

fn u32At(data: []const u8, off: usize) DwarfError!u32 {
    if (off > data.len or data.len - off < 4) return error.Corrupt;
    var b0: u32 = @intCast(u32, data[off]);
    var b1: u32 = @intCast(u32, data[off + 1]);
    var b2: u32 = @intCast(u32, data[off + 2]);
    var b3: u32 = @intCast(u32, data[off + 3]);
    return b0 | (b1 << @intCast(u32, 8)) | (b2 << @intCast(u32, 16)) | (b3 << @intCast(u32, 24));
}

fn readUleb(data: []const u8, pos: *usize, limit: usize) DwarfError!u64 {
    var result: u64 = 0;
    var shift: u32 = 0;
    while (pos.* < limit and pos.* < data.len) {
        var b = data[pos.*];
        pos.* += 1;
        var part: u64 = @intCast(u64, b & @intCast(u8, 0x7f));
        if (shift >= 64) return error.Corrupt;
        // Reject a ULEB that would not fit u64 before shifting (Z98's `<<`
        // is a checked shift; a lost bit would otherwise trap).
        if (part != 0 and part > (0xFFFFFFFFFFFFFFFF >> shift)) return error.Corrupt;
        result = result | (part << shift);
        if ((b & @intCast(u8, 0x80)) == 0) return result;
        shift += 7;
    }
    return error.Corrupt;
}

fn readSleb(data: []const u8, pos: *usize, limit: usize) DwarfError!i64 {
    var result: u64 = 0;
    var shift: u32 = 0;
    while (pos.* < limit and pos.* < data.len) {
        var b = data[pos.*];
        pos.* += 1;
        var part: u64 = @intCast(u64, b & @intCast(u8, 0x7f));
        if (shift >= 64) return error.Corrupt;
        if (part != 0 and part > (0xFFFFFFFFFFFFFFFF >> shift)) return error.Corrupt;
        result = result | (part << shift);
        shift += 7;
        if ((b & @intCast(u8, 0x80)) == 0) {
            if (shift < 64 and (b & @intCast(u8, 0x40)) != 0) {
                // Sign-extend without shifting a full-width all-ones mask
                // (that loses bits and trips the checked shift).
                var one: u64 = 1;
                var lowmask: u64 = 0;
                lowmask = (one << shift) - 1;
                result = result | (~lowmask);
            }
            return @bitCast(i64, result);
        }
    }
    return error.Corrupt;
}

fn ulebUsize(data: []const u8, pos: *usize, limit: usize) DwarfError!usize {
    var v = try readUleb(data, pos, limit);
    if (v > 4294967295) return error.Corrupt;
    return @intCast(usize, v);
}

fn cstr(data: []const u8, off: usize, limit: usize, next: *usize) DwarfError![]const u8 {
    var i = off;
    while (i < limit and i < data.len) : (i += 1) {
        if (data[i] == 0) {
            next.* = i + 1;
            return data[off..i];
        }
    }
    return error.Corrupt;
}

fn skipCstr(data: []const u8, off: *usize, limit: usize) DwarfError!bool {
    var next: usize = 0;
    var s = try cstr(data, off.*, limit, &next);
    off.* = next;
    return s.len == 0;
}

pub fn basename(path: []const u8) []const u8 {
    var i: usize = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') return path[i + 1 ..];
    }
    return path;
}

fn nameEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn growRows(p: *Parser) DwarfError!void {
    if (p.row_n < p.row_cap) return;
    var ncap = p.row_cap;
    if (ncap == 0) {
        ncap = 1024;
    } else {
        ncap *= 2;
    }
    if (ncap > MAX_ROWS) ncap = MAX_ROWS;
    if (p.row_n >= ncap) return error.Corrupt;
    var raw = std.arena.alloc(p.arena, @sizeOf(Row) * ncap) catch return error.OutOfMemory;
    var dst = @ptrCast([*]Row, raw);
    var i: usize = 0;
    while (i < p.row_n) : (i += 1) dst[i] = p.rows[i];
    p.rows = dst;
    p.row_cap = ncap;
}

fn growFiles(p: *Parser) DwarfError!void {
    if (p.file_n < p.file_cap) return;
    var ncap = p.file_cap;
    if (ncap == 0) {
        ncap = 64;
    } else {
        ncap *= 2;
    }
    var raw = std.arena.alloc(p.arena, @sizeOf([]const u8) * ncap) catch return error.OutOfMemory;
    var dst = @ptrCast([*][]const u8, raw);
    var i: usize = 0;
    while (i < p.file_n) : (i += 1) dst[i] = p.files[i];
    p.files = dst;
    p.file_cap = ncap;
}

fn growFuncs(p: *Parser) DwarfError!void {
    if (p.func_n < p.func_cap) return;
    var ncap = p.func_cap;
    if (ncap == 0) {
        ncap = 64;
    } else {
        ncap *= 2;
    }
    var raw = std.arena.alloc(p.arena, @sizeOf(Func) * ncap) catch return error.OutOfMemory;
    var dst = @ptrCast([*]Func, raw);
    var i: usize = 0;
    while (i < p.func_n) : (i += 1) dst[i] = p.funcs[i];
    p.funcs = dst;
    p.func_cap = ncap;
}

fn addFile(p: *Parser, name: []const u8) DwarfError!void {
    try growFiles(p);
    p.files[p.file_n] = name;
    p.file_n += 1;
}

fn addFunc(p: *Parser, addr: u32, size: u32, name: []const u8) DwarfError!void {
    try growFuncs(p);
    p.funcs[p.func_n] = Func{ .addr = addr, .size = size, .name = name };
    p.func_n += 1;
}

fn emitRow(p: *Parser, st: *LState, file_base: u32, file_count: *u32, end: bool) DwarfError!void {
    try growRows(p);
    var line: u32 = 0;
    if (st.line > 0 and st.line <= 4294967295) line = @intCast(u32, st.line);
    var gidx: u32 = 0xFFFFFFFF;
    if (st.file >= 1 and st.file <= file_count.*) {
        gidx = file_base + (st.file - 1);
    }
    p.rows[p.row_n] = Row{ .addr = st.addr, .line = line, .file = gidx, .end = end };
    p.row_n += 1;
}

fn applyAddrAdvance(st: *LState, min_inst: u8, max_ops: u8, op_adv: u32) void {
    var mi: u32 = @intCast(u32, min_inst);
    if (max_ops <= 1) {
        st.addr +%= op_adv *% mi;
        return;
    }
    var mo: u32 = @intCast(u32, max_ops);
    var total = st.op_index +% op_adv;
    st.addr +%= (total / mo) *% mi;
    st.op_index = total % mo;
}

fn parseProgram(p: *Parser, prog_start: usize, unit_end: usize, version: u16, min_inst: u8, max_ops: u8, default_is_stmt: bool, line_base: i8, line_range: u8, opcode_base: u8, op_lengths: []const u8, file_base: u32, file_count: *u32) DwarfError!void {
    var st = LState{ .addr = 0, .file = 1, .line = 1, .is_stmt = default_is_stmt, .op_index = 0 };
    var pos = prog_start;
    while (pos < unit_end) {
        var op = try u8At(p.data, pos);
        pos += 1;
        if (op == 0) {
            var len = try ulebUsize(p.data, &pos, unit_end);
            if (len == 0) continue;
            if (pos > unit_end or unit_end - pos < len) return error.Corrupt;
            var sub_end = pos + len;
            var sub = try u8At(p.data, pos);
            pos += 1;
            if (sub == 1) {
                try emitRow(p, &st, file_base, file_count, true);
                st.addr = 0;
                st.file = 1;
                st.line = 1;
                st.is_stmt = default_is_stmt;
                st.op_index = 0;
            } else if (sub == 2) {
                var operand_len = len - 1;
                if (operand_len >= 4 and pos + 4 <= sub_end) {
                    st.addr = try u32At(p.data, pos);
                }
                st.op_index = 0;
            } else if (sub == 3) {
                var next: usize = 0;
                var fname = try cstr(p.data, pos, sub_end, &next);
                pos = next;
                _ = try readUleb(p.data, &pos, sub_end);
                _ = try readUleb(p.data, &pos, sub_end);
                _ = try readUleb(p.data, &pos, sub_end);
                if (fname.len > 0) {
                    try addFile(p, fname);
                    file_count.* += 1;
                }
            }
            pos = sub_end;
            continue;
        }
        if (op < opcode_base) {
            if (op == 1) {
                try emitRow(p, &st, file_base, file_count, false);
            } else if (op == 2) {
                var adv = try ulebUsize(p.data, &pos, unit_end);
                applyAddrAdvance(&st, min_inst, max_ops, @intCast(u32, adv));
            } else if (op == 3) {
                var adv = try readSleb(p.data, &pos, unit_end);
                st.line = st.line +% adv;
            } else if (op == 4) {
                var f = try ulebUsize(p.data, &pos, unit_end);
                if (f > 4294967295) return error.Corrupt;
                st.file = @intCast(u32, f);
            } else if (op == 5) {
                _ = try readUleb(p.data, &pos, unit_end);
            } else if (op == 6) {
                st.is_stmt = !st.is_stmt;
            } else if (op == 7) {
                // set_basic_block: no state we track
            } else if (op == 8) {
                if (line_range != 0) {
                    var op_adv: u32 = @intCast(u32, (@intCast(u32, 255) - @intCast(u32, opcode_base)) / @intCast(u32, line_range));
                    applyAddrAdvance(&st, min_inst, max_ops, op_adv);
                }
            } else if (op == 9) {
                if (pos + 2 > unit_end) return error.Corrupt;
                var adv = try u16At(p.data, pos);
                pos += 2;
                st.addr +%= @intCast(u32, adv);
                st.op_index = 0;
            } else if (op == 10 or op == 11) {
                // prologue_end / epilogue_begin
            } else if (op == 12) {
                _ = try readUleb(p.data, &pos, unit_end);
            } else {
                var nargs: u8 = 0;
                if (op >= 1 and @intCast(usize, op - 1) < op_lengths.len) nargs = op_lengths[@intCast(usize, op - 1)];
                var k: u8 = 0;
                while (k < nargs) : (k += 1) {
                    _ = try readUleb(p.data, &pos, unit_end);
                }
            }
            continue;
        }
        if (line_range == 0) return error.Corrupt;
        var adjusted: u32 = @intCast(u32, op - opcode_base);
        var lr: u32 = @intCast(u32, line_range);
        var line_inc: i64 = @intCast(i64, line_base) + @intCast(i64, adjusted % lr);
        st.line = st.line +% line_inc;
        var oadv = adjusted / lr;
        applyAddrAdvance(&st, min_inst, max_ops, oadv);
        try emitRow(p, &st, file_base, file_count, false);
    }
    _ = version;
}

fn parseLineTable(p: *Parser, sec: Section) DwarfError!void {
    var start: usize = @intCast(usize, sec.sh_offset);
    var size: usize = @intCast(usize, sec.sh_size);
    if (start > p.data.len or p.data.len - start < size) return error.Corrupt;
    var pos = start;
    var end = start + size;
    while (pos + 4 <= end) {
        var unit_len = try u32At(p.data, pos);
        pos += 4;
        if (unit_len == 0xffffffff) {
            p.unsupported = true;
            return;
        }
        if (unit_len == 0) return;
        var ulen: usize = @intCast(usize, unit_len);
        if (pos > end or end - pos < ulen) return error.Corrupt;
        var unit_end = pos + ulen;
        if (pos + 2 > unit_end) return error.Corrupt;
        var version = try u16At(p.data, pos);
        pos += 2;
        if (version < 2 or version > 4) {
            p.unsupported = true;
            pos = unit_end;
            continue;
        }
        if (pos + 4 > unit_end) return error.Corrupt;
        var header_len = try u32At(p.data, pos);
        pos += 4;
        var hlen: usize = @intCast(usize, header_len);
        if (pos > unit_end or unit_end - pos < hlen) return error.Corrupt;
        var prog_start = pos + hlen;
        var min_inst = try u8At(p.data, pos);
        pos += 1;
        var max_ops: u8 = 1;
        if (version >= 4) {
            max_ops = try u8At(p.data, pos);
            pos += 1;
            if (max_ops == 0) max_ops = 1;
        }
        var default_is_stmt = try u8At(p.data, pos);
        pos += 1;
        var lb = try u8At(p.data, pos);
        pos += 1;
        var line_base: i8 = @bitCast(i8, lb);
        var line_range = try u8At(p.data, pos);
        pos += 1;
        var opcode_base = try u8At(p.data, pos);
        pos += 1;
        var op_lengths: [256]u8 = undefined;
        var z: usize = 0;
        while (z < 256) : (z += 1) op_lengths[z] = 0;
        if (opcode_base > 1) {
            var n = @intCast(usize, opcode_base - 1);
            if (pos > prog_start or prog_start - pos < n) return error.Corrupt;
            var q: usize = 0;
            while (q < n) : (q += 1) {
                op_lengths[q] = try u8At(p.data, pos);
                pos += 1;
            }
        }
        // include_directories: NUL-terminated, empty string terminates
        while (true) {
            var empty = try skipCstr(p.data, &pos, prog_start);
            if (empty) break;
        }
        var file_base: u32 = @intCast(u32, p.file_n);
        var file_count: u32 = 0;
        // file_names: name\0 dir mtime size, empty name terminates
        while (true) {
            var next: usize = 0;
            var fname = try cstr(p.data, pos, prog_start, &next);
            pos = next;
            if (fname.len == 0) break;
            try addFile(p, fname);
            file_count += 1;
            _ = try readUleb(p.data, &pos, prog_start);
            _ = try readUleb(p.data, &pos, prog_start);
            _ = try readUleb(p.data, &pos, prog_start);
        }
        try parseProgram(p, prog_start, unit_end, version, min_inst, max_ops, default_is_stmt != 0, line_base, line_range, opcode_base, op_lengths[0..], file_base, &file_count);
        pos = unit_end;
    }
}

fn sectionAt(data: []const u8, shoff: usize, entsize: usize, idx: usize) DwarfError!Section {
    var off = shoff + idx * entsize;
    return Section{
        .name_off = try u32At(data, off),
        .sh_type = try u32At(data, off + 4),
        .sh_offset = try u32At(data, off + 16),
        .sh_size = try u32At(data, off + 20),
        .sh_link = try u32At(data, off + 24),
        .sh_entsize = try u32At(data, off + 36),
    };
}

fn findSectionName(data: []const u8, shoff: usize, entsize: usize, shnum: usize, shstrndx: usize, want: []const u8) DwarfError!?Section {
    if (shstrndx >= shnum) return error.Corrupt;
    var str_sec = try sectionAt(data, shoff, entsize, shstrndx);
    var sstart: usize = @intCast(usize, str_sec.sh_offset);
    var ssize: usize = @intCast(usize, str_sec.sh_size);
    if (sstart > data.len or data.len - sstart < ssize) return error.Corrupt;
    var i: usize = 0;
    while (i < shnum) : (i += 1) {
        var s = try sectionAt(data, shoff, entsize, i);
        var noff: usize = @intCast(usize, s.name_off);
        if (noff >= ssize) continue;
        var next: usize = 0;
        var nm = try cstr(data, sstart + noff, sstart + ssize, &next);
        if (nameEql(nm, want)) return s;
    }
    return null;
}

fn parseSymtab(p: *Parser, sym: Section, str: Section) DwarfError!void {
    if (sym.sh_entsize < 16) return error.Corrupt;
    var sstart: usize = @intCast(usize, sym.sh_offset);
    var ssize: usize = @intCast(usize, sym.sh_size);
    if (sstart > p.data.len or p.data.len - sstart < ssize) return error.Corrupt;
    var tstart: usize = @intCast(usize, str.sh_offset);
    var tsize: usize = @intCast(usize, str.sh_size);
    if (tstart > p.data.len or p.data.len - tstart < tsize) return error.Corrupt;
    var entsize: usize = @intCast(usize, sym.sh_entsize);
    var count = ssize / entsize;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var off = sstart + i * entsize;
        var name_off = try u32At(p.data, off);
        var value = try u32At(p.data, off + 4);
        var sz = try u32At(p.data, off + 8);
        var info = try u8At(p.data, off + 12);
        var shndx = try u16At(p.data, off + 14);
        if ((info & @intCast(u8, 0x0f)) != 2) continue;
        if (value == 0 or shndx == 0) continue;
        var noff: usize = @intCast(usize, name_off);
        if (noff >= tsize) continue;
        var next: usize = 0;
        var nm = try cstr(p.data, tstart + noff, tstart + tsize, &next);
        if (nm.len == 0) continue;
        try addFunc(p, value, sz, nm);
    }
}

fn rowLess(a: Row, b: Row) bool {
    if (a.addr != b.addr) return a.addr < b.addr;
    if (a.line != b.line) return a.line < b.line;
    if (a.end == b.end) return false;
    return !a.end;
}

fn rowSift(rows: [*]Row, n: usize, root: usize) void {
    var r = root;
    while (true) {
        var child = r * 2 + 1;
        if (child >= n) return;
        if (child + 1 < n and rowLess(rows[child], rows[child + 1])) child += 1;
        if (!rowLess(rows[r], rows[child])) return;
        var tmp = rows[r];
        rows[r] = rows[child];
        rows[child] = tmp;
        r = child;
    }
}

fn sortRows(rows: [*]Row, n: usize) void {
    if (n < 2) return;
    var i: usize = n / 2;
    while (i > 0) {
        i -= 1;
        rowSift(rows, n, i);
    }
    var end: usize = n;
    while (end > 1) {
        end -= 1;
        var tmp = rows[0];
        rows[0] = rows[end];
        rows[end] = tmp;
        rowSift(rows, end, 0);
    }
}

fn funcSift(funcs: [*]Func, n: usize, root: usize) void {
    var r = root;
    while (true) {
        var child = r * 2 + 1;
        if (child >= n) return;
        if (child + 1 < n and funcs[child].addr < funcs[child + 1].addr) child += 1;
        if (funcs[r].addr >= funcs[child].addr) return;
        var tmp = funcs[r];
        funcs[r] = funcs[child];
        funcs[child] = tmp;
        r = child;
    }
}

fn sortFuncs(funcs: [*]Func, n: usize) void {
    if (n < 2) return;
    var i: usize = n / 2;
    while (i > 0) {
        i -= 1;
        funcSift(funcs, n, i);
    }
    var end: usize = n;
    while (end > 1) {
        end -= 1;
        var tmp = funcs[0];
        funcs[0] = funcs[end];
        funcs[end] = tmp;
        funcSift(funcs, end, 0);
    }
}

pub fn open(arena: *std.arena.Arena, exe: []const u8) DwarfError!DebugInfo {
    var data = file_mod.readAll(arena, exe) catch return error.OpenFailed;
    if (data.len < 52) return error.NotElf;
    if (data[0] != 0x7f or data[1] != 'E' or data[2] != 'L' or data[3] != 'F') return error.NotElf;
    if (data[4] != 1 or data[5] != 1) return error.NotElf;

    var e_type = try u16At(data, 16);
    var shoff: usize = @intCast(usize, try u32At(data, 32));
    var shentsize = try u16At(data, 46);
    var shnum = try u16At(data, 48);
    var shstrndx = try u16At(data, 50);
    if (shentsize < 40 or shoff > data.len) return error.NotElf;

    var p = Parser{
        .arena = arena,
        .data = data,
        .rows = undefined,
        .row_n = 0,
        .row_cap = 0,
        .files = undefined,
        .file_n = 0,
        .file_cap = 0,
        .funcs = undefined,
        .func_n = 0,
        .func_cap = 0,
        .unsupported = false,
    };

    var line_sec = try findSectionName(data, shoff, @intCast(usize, shentsize), @intCast(usize, shnum), @intCast(usize, shstrndx), ".debug_line");
    if (line_sec) |ls| {
        parseLineTable(&p, ls) catch {
            p.row_n = 0;
            p.file_n = 0;
        };
    }
    var sym_sec = try findSectionName(data, shoff, @intCast(usize, shentsize), @intCast(usize, shnum), @intCast(usize, shstrndx), ".symtab");
    if (sym_sec) |ss| {
        if (ss.sh_link < @intCast(u32, shnum)) {
            var str_sec = try sectionAt(data, shoff, @intCast(usize, shentsize), @intCast(usize, ss.sh_link));
            parseSymtab(&p, ss, str_sec) catch {
                p.func_n = 0;
            };
        }
    }

    if (p.row_n > 1) sortRows(p.rows, p.row_n);
    if (p.func_n > 1) sortFuncs(p.funcs, p.func_n);

    return DebugInfo{
        .arena = arena,
        .data = data,
        .base = 0,
        .e_type = e_type,
        .rows = p.rows,
        .row_n = p.row_n,
        .files = p.files,
        .file_n = p.file_n,
        .funcs = p.funcs,
        .func_n = p.func_n,
        .has_line = p.row_n > 0,
        .unsupported_version = p.unsupported,
        .bias_unknown = false,
    };
}

fn hexVal(c: u8) i32 {
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(i32, c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(i32, c - 'A' + 10);
    return -1;
}

fn parseHex(s: []const u8, pos: *usize, end: usize) u32 {
    var v: u32 = 0;
    while (pos.* < end) {
        var h = hexVal(s[pos.*]);
        if (h < 0) break;
        v = v *% @intCast(u32, 16) +% @intCast(u32, h);
        pos.* += 1;
    }
    return v;
}

fn skipSpaces(s: []const u8, pos: *usize, end: usize) void {
    while (pos.* < end and (s[pos.*] == ' ' or s[pos.*] == '\t')) pos.* += 1;
}

fn readProcMaps(arena: *std.arena.Arena, pid: i32) ?[]const u8 {
    var nbuf: [32]u8 = undefined;
    var n: usize = 0;
    var prefix: []const u8 = "/proc/";
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        nbuf[n] = prefix[i];
        n += 1;
    }
    if (pid == 0) return null;
    var tmp: [12]u8 = undefined;
    var tn: usize = 0;
    var v: i32 = pid;
    if (v < 0) return null;
    if (v == 0) {
        tmp[0] = '0';
        tn = 1;
    } else {
        while (v > 0) : (v = v / 10) {
            tmp[tn] = @intCast(u8, (v % 10) + 48);
            tn += 1;
        }
    }
    while (tn > 0) {
        tn -= 1;
        nbuf[n] = tmp[tn];
        n += 1;
    }
    var suffix: []const u8 = "/maps";
    i = 0;
    while (i < suffix.len) : (i += 1) {
        nbuf[n] = suffix[i];
        n += 1;
    }
    var path = nbuf[0..n];

    var f = file_mod.open(arena, path, file_mod.Mode.Read) catch return null;
    var raw = std.arena.alloc(arena, 65536) catch {
        file_mod.close(&f);
        return null;
    };
    var buf = raw[0..65536];
    var used: usize = 0;
    while (used < buf.len) {
        var got = file_mod.read(&f, buf[used..]) catch break;
        if (got == 0) break;
        used += got;
    }
    file_mod.close(&f);
    return buf[0..used];
}

pub fn setLoadBase(di: *DebugInfo, exe: []const u8, pid: i32) bool {
    if (di.e_type != 3) {
        di.base = 0;
        di.bias_unknown = false;
        return true;
    }
    var maps = readProcMaps(di.arena, pid) orelse {
        di.base = 0;
        di.bias_unknown = true;
        return false;
    };
    var want = basename(exe);
    var ls: usize = 0;
    var fallback: u32 = 0;
    var have_fallback = false;
    while (ls < maps.len) {
        var le = ls;
        while (le < maps.len and maps[le] != '\n') : (le += 1) {}
        var line = maps[ls..le];
        var pos: usize = 0;
        var end = line.len;
        while (pos < end and line[pos] == ' ') pos += 1;
        var start_a = parseHex(line, &pos, end);
        if (pos < end and line[pos] == '-') pos += 1;
        _ = parseHex(line, &pos, end);
        skipSpaces(line, &pos, end);
        var p0: usize = pos;
        while (pos < end and line[pos] != ' ') pos += 1;
        var perms = line[p0..pos];
        skipSpaces(line, &pos, end);
        var offset = parseHex(line, &pos, end);
        skipSpaces(line, &pos, end);
        _ = parseHex(line, &pos, end);
        skipSpaces(line, &pos, end);
        while (pos < end and line[pos] != ' ') pos += 1;
        skipSpaces(line, &pos, end);
        var path = line[pos..end];
        if (path.len > 0 and path[path.len - 1] == '\r') path = path[0 .. path.len - 1];
        if (!nameEql(basename(path), want)) {
            ls = le + 1;
            continue;
        }
        if (perms.len >= 1 and perms[0] == 'r') {
            var base = start_a -% offset;
            if (offset == 0) {
                di.base = base;
                di.bias_unknown = false;
                return true;
            }
            if (!have_fallback) {
                fallback = base;
                have_fallback = true;
            }
        }
        ls = le + 1;
    }
    if (have_fallback) {
        di.base = fallback;
        di.bias_unknown = false;
        return true;
    }
    di.base = 0;
    di.bias_unknown = true;
    return false;
}

fn fileMatches(di: *const DebugInfo, idx: u32, out_file: []const u8) bool {
    if (idx >= di.file_n) return false;
    return nameEql(basename(di.files[@intCast(usize, idx)]), basename(out_file));
}

pub fn addrForLine(di: *const DebugInfo, out_file: []const u8, out_line: u32, out: []u32) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < di.row_n) : (i += 1) {
        var r = di.rows[i];
        if (r.end or r.addr == 0) continue;
        if (r.line != out_line) continue;
        if (!fileMatches(di, r.file, out_file)) continue;
        var addr = r.addr +% di.base;
        var dup = false;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            if (out[k] == addr) dup = true;
        }
        if (dup) continue;
        if (n < out.len) {
            out[n] = addr;
            n += 1;
        }
    }
    return n;
}

pub fn rowForAddr(di: *const DebugInfo, runtime_addr: u32) ?Row {
    if (!di.has_line) return null;
    var link = runtime_addr;
    if (link >= di.base) link -= di.base;
    var lo: usize = 0;
    var hi: usize = di.row_n;
    while (lo < hi) {
        var mid = lo + (hi - lo) / 2;
        if (di.rows[mid].addr <= link) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) return null;
    var r = di.rows[lo - 1];
    if (r.end) return null;
    return r;
}

pub fn rowFileName(di: *const DebugInfo, r: Row) []const u8 {
    if (r.file >= di.file_n) return "";
    return di.files[@intCast(usize, r.file)];
}

pub fn funcAddr(di: *const DebugInfo, name: []const u8) ?u32 {
    var i: usize = 0;
    while (i < di.func_n) : (i += 1) {
        if (nameEql(di.funcs[i].name, name)) return di.funcs[i].addr +% di.base;
    }
    return null;
}

pub fn funcByAddr(di: *const DebugInfo, runtime_addr: u32) ?Func {
    var link = runtime_addr;
    if (link >= di.base) link -= di.base;
    var best: ?Func = null;
    var i: usize = 0;
    while (i < di.func_n) : (i += 1) {
        var f = di.funcs[i];
        if (f.addr > link) continue;
        if (f.size != 0) {
            if (link - f.addr >= f.size) continue;
        } else if (link != f.addr) {
            continue;
        }
        var better = false;
        if (best == null) {
            better = true;
        } else if (best) |b| {
            if (f.addr > b.addr) better = true;
        }
        if (better) best = f;
    }
    return best;
}
