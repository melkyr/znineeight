// dbg_core.zig — source-level debugger core (P3-M2).
//
// Breakpoint table + spec §7.4 snap rule, stop display, and the v1
// `dump variables` snapshot writer. Source-line breakpoints are stored in
// source coordinates; machine-address resolution (DWARF/COFF + int3 plants)
// is the M3/M4 backend layer's job, so nothing here invents an address.
//
// Snap rule (binding):
//   - whitespace-only source line -> reject (no executable code), no-op;
//   - line with a map row -> the breakpoint line;
//   - otherwise snap forward to the next mapped line, stopping at the next
//     function declaration; if none, reject with the same message.

const std = @import("std");
const file_mod = @import("std_file");
const map_reader = @import("map_reader.zig");
const backend = @import("backend.zig");

pub const StopState = struct {
    src_file: []const u8,
    src_line: u32,
    function_name: []const u8,
};

pub const BreakOutcome = enum { added, moved, duplicate, no_code, table_full };

pub const BreakResult = struct {
    outcome: BreakOutcome,
    line: u32,
    src_file: []const u8,
};

const Breakpoint = struct {
    src_file: []const u8,
    line: u32,
};

const TABLE_CAP: usize = 256;

pub const BreakTable = struct {
    items: [TABLE_CAP]Breakpoint,
    len: usize,
};

pub fn breakTableInit() BreakTable {
    return BreakTable{ .items = undefined, .len = 0 };
}

fn breakTableFind(table: *BreakTable, file: []const u8, line: u32) bool {
    var i: usize = 0;
    while (i < table.len) : (i += 1) {
        if (table.items[i].line == line and std.str.eql(table.items[i].src_file, file)) return true;
    }
    return false;
}

fn breakTableAdd(table: *BreakTable, file: []const u8, line: u32) u8 {
    if (breakTableFind(table, file, line)) return 1;
    if (table.len >= TABLE_CAP) return 2;
    table.items[table.len] = Breakpoint{ .src_file = file, .line = line };
    table.len += 1;
    return 0;
}

pub fn readSourceLine(arena: *std.arena.Arena, path: []const u8, line: u32) ?[]const u8 {
    if (line == 0) return null;
    var data = file_mod.readAll(arena, path) catch return null;
    var cur: u32 = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (true) {
        var at_end = i == data.len;
        var at_nl = false;
        if (!at_end) at_nl = data[i] == '\n';
        if (at_end or at_nl) {
            if (at_end and data.len > 0 and start == data.len) return null;
            if (cur == line) {
                var end = i;
                if (end > start and data[end - 1] == '\r') end -= 1;
                return data[start..end];
            }
            if (at_end) return null;
            cur += 1;
            start = i + 1;
        }
        i += 1;
    }
    return null;
}

fn isWhitespaceOnly(s: []const u8) bool {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] != ' ' and s[i] != '\t' and s[i] != '\r') return false;
    }
    return true;
}

fn nextFunctionLine(reader: *map_reader.MapReader, file: []const u8, after: u32) ?u32 {
    var best: u32 = 0;
    var found = false;
    var i: usize = 0;
    while (i < map_reader.symbolCount(reader)) : (i += 1) {
        var sym = map_reader.symbolByIndex(reader, i) orelse continue;
        if (sym.kind != 0) continue;
        if (!std.str.eql(sym.src_file, file)) continue;
        if (sym.src_line <= after) continue;
        if (!found or sym.src_line < best) {
            best = sym.src_line;
            found = true;
        }
    }
    if (!found) return null;
    return best;
}

pub fn requestBreak(reader: *map_reader.MapReader, table: *BreakTable, arena: *std.arena.Arena, file_query: []const u8, line: u32) BreakResult {
    var file = map_reader.resolveFile(reader, file_query) orelse {
        return BreakResult{ .outcome = .no_code, .line = line, .src_file = "" };
    };
    if (line == 0) {
        return BreakResult{ .outcome = .no_code, .line = line, .src_file = file };
    }
    var text = readSourceLine(arena, file, line);
    if (text) |t| {
        if (isWhitespaceOnly(t)) {
            return BreakResult{ .outcome = .no_code, .line = line, .src_file = file };
        }
    }
    if (map_reader.lineAt(reader, file, line) != null) {
        var add = breakTableAdd(table, file, line);
        if (add == 0) return BreakResult{ .outcome = .added, .line = line, .src_file = file };
        if (add == 1) return BreakResult{ .outcome = .duplicate, .line = line, .src_file = file };
        return BreakResult{ .outcome = .table_full, .line = line, .src_file = file };
    }

    if (line == 4294967295) {
        return BreakResult{ .outcome = .no_code, .line = line, .src_file = file };
    }
    var target = line + 1;
    var next_opt = map_reader.nextMappedLine(reader, file, target);
    if (next_opt) |m| {
        var nf_opt = nextFunctionLine(reader, file, line);
        var blocked = false;
        if (nf_opt) |nf| {
            if (m >= nf) blocked = true;
        }
        if (!blocked) {
            var add2 = breakTableAdd(table, file, m);
            if (add2 == 0) return BreakResult{ .outcome = .moved, .line = m, .src_file = file };
            if (add2 == 1) return BreakResult{ .outcome = .duplicate, .line = m, .src_file = file };
            return BreakResult{ .outcome = .table_full, .line = m, .src_file = file };
        }
    }
    return BreakResult{ .outcome = .no_code, .line = line, .src_file = file };
}

pub fn printBreakResult(res: BreakResult) void {
    switch (res.outcome) {
        .added => {
            std.io.write("break: set at line ");
            std.io.printInt(@intCast(i32, res.line));
            std.io.write("\n");
        },
        .moved => {
            std.io.write("break: moved to line ");
            std.io.printInt(@intCast(i32, res.line));
            std.io.write("\n");
        },
        .duplicate => {
            std.io.write("break: already set at line ");
            std.io.printInt(@intCast(i32, res.line));
            std.io.write("\n");
        },
        .table_full => {
            std.io.write("break: breakpoint table full\n");
        },
        else => {
            std.io.write("break: no executable code at line ");
            std.io.printInt(@intCast(i32, res.line));
            std.io.write("\n");
        },
    }
}

pub fn entryStop(reader: *map_reader.MapReader, arena: *std.arena.Arena) ?StopState {
    _ = arena;
    var sym = map_reader.functionByName(reader, "main") orelse return null;
    var line_opt = map_reader.nextMappedLine(reader, sym.src_file, sym.src_line);
    var line: u32 = 0;
    if (line_opt) |l| {
        line = l;
    } else {
        return null;
    }
    var next = nextFunctionLine(reader, sym.src_file, sym.src_line);
    if (next) |nf| {
        if (line >= nf) return null;
    }
    return StopState{ .src_file = sym.src_file, .src_line = line, .function_name = sym.src_name };
}

pub const ResolveFn = fn (*void, u32, *StopState) bool;

pub const StepOutcome = enum { stepped, unavailable, exited, exhausted };

// Step-into: single-step through the backend until a resolved stop lands on a
// mapped Z98 line different from `current` (unmapped C / same-line stops are
// skipped). Resolution of a machine stop to a source line is supplied by the
// caller (M3 wires DWARF; the M2 tests script it).
pub fn stepInto(reader: *map_reader.MapReader, be: *backend.Backend, resolve_state: *void, resolve_fn: ResolveFn, current: StopState, max_steps: u32, out: *StopState) StepOutcome {
    var steps: u32 = 0;
    while (steps < max_steps) : (steps += 1) {
        be.singleStep_fn(be.state) catch return .unavailable;
        var ev = be.wait_fn(be.state) catch return .unavailable;
        if (ev.reason == backend.STOP_EXITED) return .exited;
        var st: StopState = undefined;
        if (!resolve_fn(resolve_state, ev.eip, &st)) continue;
        var changed = !std.str.eql(st.src_file, current.src_file) or st.src_line != current.src_line;
        if (!changed) continue;
        if (map_reader.lineAt(reader, st.src_file, st.src_line) != null) {
            out.* = st;
            return .stepped;
        }
    }
    return .exhausted;
}

fn printSourceLine(arena: *std.arena.Arena, file: []const u8, line: u32, current: bool) void {
    var text_opt = readSourceLine(arena, file, line);
    var text: []const u8 = "";
    if (text_opt) |t| {
        text = t;
    } else {
        return;
    }
    if (current) {
        std.io.write("> ");
    } else {
        std.io.write("  ");
    }
    std.io.printInt(@intCast(i32, line));
    if (text.len > 0) {
        std.io.write(": ");
        std.io.write(text);
    } else {
        std.io.write(":");
    }
    std.io.write("\n");
}

pub fn printStop(reader: *map_reader.MapReader, arena: *std.arena.Arena, stop: StopState) void {
    _ = reader;
    std.io.write("Stopped at ");
    std.io.write(stop.src_file);
    std.io.write(":");
    std.io.printInt(@intCast(i32, stop.src_line));
    std.io.write("\n");
    std.io.write("at ");
    std.io.write(stop.function_name);
    std.io.write("\n");
    var start: u32 = 1;
    if (stop.src_line > 2) start = stop.src_line - 2;
    var end = stop.src_line + 2;
    var line = start;
    while (true) {
        printSourceLine(arena, stop.src_file, line, line == stop.src_line);
        if (line == end) break;
        if (line == 4294967295) break;
        line += 1;
    }
}

const TextBuf = struct {
    data: []u8,
    len: usize,
};

fn tbAppend(tb: *TextBuf, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (tb.len >= tb.data.len) return;
        tb.data[tb.len] = s[i];
        tb.len += 1;
    }
}

fn tbU32(tb: *TextBuf, v: u32) void {
    if (v == 0) {
        tbAppend(tb, "0");
        return;
    }
    var tmp: [10]u8 = undefined;
    var n: usize = 0;
    var x = v;
    while (x > 0) : (x /= 10) {
        tmp[n] = @intCast(u8, (x % 10) + 48);
        n += 1;
    }
    while (n > 0) {
        n -= 1;
        if (tb.len >= tb.data.len) return;
        tb.data[tb.len] = tmp[n];
        tb.len += 1;
    }
}

fn hexNibble(v: u32) u8 {
    if (v < 10) return @intCast(u8, v + 48);
    return @intCast(u8, v + 87);
}

fn tbHex8(tb: *TextBuf, v: u32) void {
    tbAppend(tb, "0x");
    var shift: u32 = 28;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        var nib = (v >> shift) & @intCast(u32, 15);
        if (tb.len >= tb.data.len) return;
        tb.data[tb.len] = hexNibble(nib);
        tb.len += 1;
        if (shift == 0) break;
        shift -= 4;
    }
}

pub fn writeDump(reader: *map_reader.MapReader, arena: *std.arena.Arena, stop: StopState, path: []const u8, regs: backend.Registers, regs_ok: bool) bool {
    var raw = std.arena.alloc(arena, 65536) catch return false;
    var tb = TextBuf{ .data = raw[0..65536], .len = 0 };
    tbAppend(&tb, "Z98 debugger variables v1\n");
    tbAppend(&tb, "stopped at ");
    tbAppend(&tb, stop.src_file);
    tbAppend(&tb, ":");
    tbU32(&tb, stop.src_line);
    tbAppend(&tb, "\n");
    tbAppend(&tb, "function ");
    tbAppend(&tb, stop.function_name);
    tbAppend(&tb, "\n");
    tbAppend(&tb, "registers\n");
    if (regs_ok) {
        tbAppend(&tb, "  eax=");
        tbHex8(&tb, regs.eax);
        tbAppend(&tb, " ecx=");
        tbHex8(&tb, regs.ecx);
        tbAppend(&tb, " edx=");
        tbHex8(&tb, regs.edx);
        tbAppend(&tb, " ebx=");
        tbHex8(&tb, regs.ebx);
        tbAppend(&tb, "\n");
        tbAppend(&tb, "  esp=");
        tbHex8(&tb, regs.esp);
        tbAppend(&tb, " ebp=");
        tbHex8(&tb, regs.ebp);
        tbAppend(&tb, " esi=");
        tbHex8(&tb, regs.esi);
        tbAppend(&tb, " edi=");
        tbHex8(&tb, regs.edi);
        tbAppend(&tb, "\n");
        tbAppend(&tb, "  eip=");
        tbHex8(&tb, regs.eip);
        tbAppend(&tb, " eflags=");
        tbHex8(&tb, regs.eflags);
        tbAppend(&tb, "\n");
    } else {
        tbAppend(&tb, "  unavailable\n");
    }
    tbAppend(&tb, "call stack\n");
    tbAppend(&tb, "  #0 ");
    tbAppend(&tb, stop.function_name);
    tbAppend(&tb, " at ");
    tbAppend(&tb, stop.src_file);
    tbAppend(&tb, ":");
    tbU32(&tb, stop.src_line);
    tbAppend(&tb, "\n");
    tbAppend(&tb, "globals\n");
    var any: bool = false;
    var i: usize = 0;
    while (i < map_reader.symbolCount(reader)) : (i += 1) {
        var sym = map_reader.symbolByIndex(reader, i) orelse continue;
        if (sym.kind != 1) continue;
        any = true;
        tbAppend(&tb, "  ");
        tbAppend(&tb, sym.src_name);
        tbAppend(&tb, " ");
        tbAppend(&tb, sym.src_file);
        tbAppend(&tb, ":");
        tbU32(&tb, sym.src_line);
        tbAppend(&tb, " module ");
        tbAppend(&tb, sym.module_stem);
        tbAppend(&tb, "\n");
    }
    if (!any) tbAppend(&tb, "  (none)\n");
    file_mod.writeAll(path, tb.data[0..tb.len]) catch return false;
    return true;
}
