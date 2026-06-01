pub const DiagnosticLevel = enum(u8) {
    err_lvl = 0,
    warning = 1,
    info = 2,
    note = 3,
};

pub const ErrorCode = enum(u16) {
    ERR_1000_UNTERMINATED_STRING,
    ERR_1001_UNTERMINATED_BLOCK_COMMENT,
    ERR_1002_INVALID_CHAR_LITERAL,
    ERR_1003_INVALID_ESCAPE,
    ERR_1004_BARE_AT_SIGN,
    ERR_1005_UNRECOGNIZED_CHAR,
    WARN_1010_UNRECOGNIZED_ESCAPE,
    WARN_1011_INTEGER_OVERFLOW,
    ERR_2000_UNEXPECTED_TOKEN,
    ERR_2001_MISSING_SEMICOLON,
    ERR_2002_UNCLOSED_BRACE,
    ERR_2003_EXPECTED_EXPRESSION,
    ERR_2004_EXPECTED_TYPE,
    WARN_2010_DEPRECATED_SYNTAX,
    ERR_2010_VOID_PARAMETER,
    ERR_2011_INCOMPLETE_TYPE,
    ERR_2012_ANYTYPE_NOT_SUPPORTED,
    ERR_2013_OPAQUE_NOT_SUPPORTED,
    WARN_7010_LARGE_RETURN,
    ERR_3000_TYPE_MISMATCH,
    ERR_3001_UNDEFINED_SYMBOL,
    ERR_3002_INVALID_ASSIGNMENT,
    ERR_3003_MISSING_RETURN,
    ERR_3004_SWITCH_NOT_EXHAUSTIVE,
    ERR_3005_CIRCULAR_TYPE_DEPENDENCY,
    ERR_3006_INVALID_COERCION,
    ERR_3007_VISIBILITY_VIOLATION,
    WARN_3010_UNUSED_VARIABLE,
    WARN_3011_UNREACHABLE_CODE,
    ERR_4000_INVALID_CONTROL_FLOW,
    ERR_4001_UNRESOLVED_TYPE_IN_LOWER,
    ERR_4002_DEFER_IN_INVALID_SCOPE,
    ERR_5000_C89_UNSUPPORTED_FEATURE,
    ERR_5001_MANGLE_OVERFLOW,
    ERR_5002_EMPTY_AGGREGATE,
    ERR_2020_RETURNING_ADDRESS_OF_LOCAL,
    ERR_2021_RETURNING_ADDRESS_OF_PARAM,
    WARN_6010_RETURNING_POINTER_VIA_VARIABLE,
    WARN_6011_RETURNING_SLICE_OF_LOCAL,
    ERR_2004_DEFINITE_NULL_DEREF,
    ERR_2005_DOUBLE_FREE,
    WARN_6001_UNINIT_DEREF,
    WARN_6002_POTENTIAL_NULL_DEREF,
    WARN_6005_MEMORY_LEAK,
    WARN_6006_FREEING_UNTRACKED,
    INFO_7001_OWNERSHIP_TRANSFERRED,
    WARN_7002_ANALYZER_BUDGET_EXCEEDED,
    ERR_9000_OOM,
    ERR_9001_ICE,
    ERR_9999_TOO_MANY_ERRORS,
};

pub const ERR_1000_UNTERMINATED_STRING: u16 = 0;
pub const ERR_1001_UNTERMINATED_BLOCK_COMMENT: u16 = 1;
pub const ERR_1002_INVALID_CHAR_LITERAL: u16 = 2;
pub const ERR_1003_INVALID_ESCAPE: u16 = 3;
pub const ERR_1004_BARE_AT_SIGN: u16 = 4;
pub const ERR_1005_UNRECOGNIZED_CHAR: u16 = 5;
pub const WARN_1010_UNRECOGNIZED_ESCAPE: u16 = 6;
pub const WARN_1011_INTEGER_OVERFLOW: u16 = 7;

pub const MAX_DIAGNOSTICS: usize = 256;

pub const Diagnostic = struct {
    level: u8,
    code: u16,
    file_id: u32,
    span_start: u32,
    span_end: u32,
    message_id: u32,
    note_count: u8,
    note_ids: [3]u32,
    related_span_idx: u16,
};

pub const RelatedSpan = struct {
    span_file_id: u32,
    span_start: u32,
    span_end: u32,
    message_id: u32,
};

const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const sm_mod = @import("source_manager.zig");
const mem_mod = @import("util/mem.zig");
const SourceManager = sm_mod.SourceManager;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;

const pal = @import("pal.zig");

fn getLevelName(level: u8) []const u8 {
    switch (level) {
        0 => {
            var s: []const u8 = "error";
            return s;
        },
        1 => {
            var s: []const u8 = "warning";
            return s;
        },
        2 => {
            var s: []const u8 = "info";
            return s;
        },
        3 => {
            var s: []const u8 = "note";
            return s;
        },
        else => {
            var s: []const u8 = "unknown";
            return s;
        },
    }
}

fn formatU32(value: u32, buf: []u8) u32 {
    var v = value;
    var i: u32 = @intCast(u32, buf.len);
    if (v == 0) {
        i -= 1;
        buf[@intCast(usize, i)] = '0';
    } else {
        while (v > 0 and i > 0) {
            i -= 1;
            buf[@intCast(usize, i)] = '0' + @intCast(u8, v % 10);
            v = v / 10;
        }
    }
    return @intCast(u32, buf.len) - i;
}

fn writeStr(s: []const u8) void {
    pal.stderr_write(s);
}

fn compareDiag(a: *const Diagnostic, b: *const Diagnostic) i32 {
    if (a.file_id != b.file_id) return @intCast(i32, a.file_id) - @intCast(i32, b.file_id);
    if (a.span_start != b.span_start) return @intCast(i32, a.span_start) - @intCast(i32, b.span_start);
    if (a.level != b.level) return @intCast(i32, a.level) - @intCast(i32, b.level);
    return 0;
}

fn sortDiagnostics(diags: []Diagnostic) void {
    var i: usize = 1;
    while (i < diags.len) {
        var key = diags[i];
        var j: i32 = @intCast(i32, i);
        while (j > 0 and compareDiag(&diags[@intCast(usize, j - 1)], &key) > 0) {
            diags[@intCast(usize, j)] = diags[@intCast(usize, j - 1)];
            j -= 1;
        }
        diags[@intCast(usize, j)] = key;
        i += 1;
    }
}

pub const DiagnosticArrayList = struct {
    items: [*]Diagnostic,
    len: usize,
    capacity: usize,
    allocator: *Sand,
};

pub fn diagnosticArrayListInit(allocator: *Sand) DiagnosticArrayList {
    return DiagnosticArrayList{
        .items = undefined,
        .len = @intCast(usize, 0),
        .capacity = @intCast(usize, 0),
        .allocator = allocator,
    };
}

pub fn diagnosticArrayListEnsureCapacity(self: *DiagnosticArrayList, new_capacity: usize) void {
    if (new_capacity <= self.capacity) return;
    var new_cap = new_capacity;
    if (new_cap < self.capacity * 2) new_cap = self.capacity * 2;
    if (new_cap < 8) new_cap = 8;
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, @sizeOf(Diagnostic)) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]Diagnostic, raw);
    for (self.items[0..self.len]) |item, i| {
        new_items[i] = item;
    }
    self.items = new_items;
    self.capacity = new_cap;
}

pub fn diagnosticArrayListAppend(self: *DiagnosticArrayList, value: Diagnostic) void {
    diagnosticArrayListEnsureCapacity(self, self.len + 1);
    self.items[self.len] = value;
    self.len += 1;
}

pub fn diagnosticArrayListGetSlice(self: *DiagnosticArrayList) []Diagnostic {
    return self.items[0..self.len];
}

pub const DiagnosticCollector = struct {
    diagnostics: *DiagnosticArrayList,
    related_span_items: [*]RelatedSpan,
    related_span_len: usize,
    related_span_cap: usize,
    allocator: *Sand,
    source_manager: *SourceManager,
    interner: *StringInterner,
    error_count: usize,
    warning_count: usize,
    max_diagnostics: usize,
};

pub fn diagnosticCollectorInit(allocator: *Sand, source_manager: *SourceManager, interner: *StringInterner) DiagnosticCollector {
    var d_raw = alloc_mod.sandAlloc(allocator, @intCast(usize, 16), @intCast(usize, 4)) catch unreachable;
    var d_ptr = @ptrCast(*DiagnosticArrayList, d_raw);
    d_ptr.* = diagnosticArrayListInit(allocator);
    return DiagnosticCollector{
        .diagnostics = d_ptr,
        .related_span_items = undefined,
        .related_span_len = @intCast(usize, 0),
        .related_span_cap = @intCast(usize, 0),
        .allocator = allocator,
        .source_manager = source_manager,
        .interner = interner,
        .error_count = @intCast(usize, 0),
        .warning_count = @intCast(usize, 0),
        .max_diagnostics = MAX_DIAGNOSTICS,
    };
}

pub fn diagnosticCollectorIntern(self: *DiagnosticCollector, msg: []const u8) u32 {
    return interner_mod.stringInternerIntern(self.interner, msg);
}

pub fn diagnosticCollectorAdd(self: *DiagnosticCollector, level: u8, code: u16, file_id: u32, span_start: u32, span_end: u32, message: []const u8) u32 {
    if (code == 9999) return @intCast(u32, 0);
    if (self.diagnostics.len >= self.max_diagnostics) {
        var overflow_msg: []const u8 = "too many errors, stopping";
        var msg_id = interner_mod.stringInternerIntern(self.interner, overflow_msg);
        diagnosticArrayListAppend(self.diagnostics, Diagnostic{
            .level = @intCast(u8, 0),
            .code = @intCast(u16, 9999),
            .file_id = file_id,
            .span_start = span_start,
            .span_end = span_end,
            .message_id = msg_id,
            .note_count = @intCast(u8, 0),
            .note_ids = [3]u32{ @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0) },
            .related_span_idx = @intCast(u16, 0),
        });
        self.error_count += 1;
        return @intCast(u32, 0);
    }
    var msg_id = interner_mod.stringInternerIntern(self.interner, message);
    diagnosticArrayListAppend(self.diagnostics, Diagnostic{
        .level = level,
        .code = code,
        .file_id = file_id,
        .span_start = span_start,
        .span_end = span_end,
        .message_id = msg_id,
        .note_count = @intCast(u8, 0),
        .note_ids = [3]u32{ @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0) },
        .related_span_idx = @intCast(u16, 0),
    });
    if (level == 0) self.error_count += 1;
    else if (level == 1) self.warning_count += 1;
    return @intCast(u32, self.diagnostics.len - 1);
}

pub fn diagnosticCollectorHasErrors(self: *DiagnosticCollector) bool {
    return self.error_count > 0;
}

pub fn diagnosticCollectorErrorCount(self: *DiagnosticCollector) u32 {
    return @intCast(u32, self.error_count);
}

pub fn diagnosticCollectorWarningCount(self: *DiagnosticCollector) u32 {
    return @intCast(u32, self.warning_count);
}

pub fn diagnosticCollectorAddNote(self: *DiagnosticCollector, diag_idx: u32, note: []const u8) void {
    if (diag_idx >= @intCast(u32, self.diagnostics.len)) return;
    var d = &self.diagnostics.items[@intCast(usize, diag_idx)];
    if (d.note_count < 3) {
        d.note_ids[@intCast(usize, d.note_count)] = interner_mod.stringInternerIntern(self.interner, note);
        d.note_count += 1;
    }
}

pub fn diagnosticCollectorAddRelatedSpan(self: *DiagnosticCollector, diag_idx: u32,
    file_id: u32, span_start: u32, span_end: u32, msg: []const u8) void {
    if (diag_idx >= @intCast(u32, self.diagnostics.len)) return;
    var msg_id = interner_mod.stringInternerIntern(self.interner, msg);
    var new_len: usize = self.related_span_len + @intCast(usize, 1);
    if (new_len >= self.related_span_cap) {
        var new_cap = self.related_span_cap * 2;
        if (new_cap < 8) new_cap = 8;
        var sz: usize = @intCast(usize, 16) * new_cap;
        var raw = alloc_mod.sandAlloc(self.allocator, sz, @intCast(usize, 4)) catch unreachable;
        var items = @ptrCast([*]RelatedSpan, raw);
        for (self.related_span_items[0..self.related_span_len]) |item, i| {
            items[i] = item;
        }
        self.related_span_items = items;
        self.related_span_cap = new_cap;
    }
    self.related_span_items[self.related_span_len] = RelatedSpan{
        .span_file_id = file_id,
        .span_start = span_start,
        .span_end = span_end,
        .message_id = msg_id,
    };
    var rs_idx: u16 = @intCast(u16, self.related_span_len);
    self.related_span_len += 1;
    self.diagnostics.items[@intCast(usize, diag_idx)].related_span_idx = rs_idx;
}

pub fn diagnosticCollectorFlushAndExit(self: *DiagnosticCollector, exit_code: u32) void {
    diagnosticCollectorPrintAll(self);
    pal.exit(@intCast(u8, exit_code));
}

pub fn diagnosticCollectorPrintAll(self: *DiagnosticCollector) void {
    if (self.diagnostics.len == 0) return;
    var pq: []const u8 = "PA_begin\n"; pal.stderr_write(pq);
    var diags = diagnosticArrayListGetSlice(self.diagnostics);
    sortDiagnostics(diags);
    var i: usize = 0;
    while (i < self.diagnostics.len) {
        var d = &diags[i];
        if (d.file_id == @intCast(u32, 0)) {
            writeStr(getLevelName(d.level));
            var lb0: []const u8 = "[";
            writeStr(lb0);
            var code_buf0: [8]u8 = undefined;
            var code_len0 = formatU32(d.code, code_buf0[0..8]);
            var kcs0: usize = @intCast(usize, 8) - @intCast(usize, code_len0);
            writeStr(code_buf0[kcs0..@intCast(usize, 8)]);
            var rb0: []const u8 = "]: ";
            writeStr(rb0);
            if (d.message_id != @intCast(u32, 0)) {
                var entry0 = self.interner.entries_items[@intCast(usize, d.message_id)];
                writeStr(entry0.text);
            }
            var nl0: []const u8 = "\n";
            writeStr(nl0);
            i += 1; continue;
        }
        var loc = sm_mod.sourceManagerGetLocation(self.source_manager, d.file_id, d.span_start);
        var fname = sm_mod.sourceManagerGetFileName(self.source_manager, d.file_id);
        writeStr(fname);
        var pf: []const u8 = "PA_fname\n"; pal.stderr_write(pf);
        var col_s: []const u8 = ":";
        writeStr(col_s);
        var line_buf: [16]u8 = undefined;
        var line_len = formatU32(loc.line, line_buf[0..16]);
        var ls: usize = @intCast(usize, 16) - @intCast(usize, line_len);
        writeStr(line_buf[ls..@intCast(usize, 16)]);
        var col_s2: []const u8 = ":";
        writeStr(col_s2);
        var col_buf: [16]u8 = undefined;
        var col_len = formatU32(loc.col, col_buf[0..16]);
        var cs: usize = @intCast(usize, 16) - @intCast(usize, col_len);
        writeStr(col_buf[cs..@intCast(usize, 16)]);
        var sep: []const u8 = ": ";
        writeStr(sep);
        writeStr(getLevelName(d.level));
        var lb: []const u8 = "[";
        writeStr(lb);
        var code_buf: [8]u8 = undefined;
        var code_len = formatU32(d.code, code_buf[0..8]);
        var kcs: usize = @intCast(usize, 8) - @intCast(usize, code_len);
        writeStr(code_buf[kcs..@intCast(usize, 8)]);
        var rb: []const u8 = "]: ";
        writeStr(rb);
        if (d.message_id != @intCast(u32, 0)) {
        var entry = self.interner.entries_items[@intCast(usize, d.message_id)];
        writeStr(entry.text);
        } else { var em: []const u8 = "(no message)"; writeStr(em); }
        var nl: []const u8 = "\n";
        writeStr(nl);
        var content = sm_mod.sourceManagerGetSourceContent(self.source_manager, d.file_id);
        var offsets = sm_mod.sourceManagerGetLineOffsets(self.source_manager, d.file_id);
        var line_idx = mem_mod.binary_search(offsets, d.span_start);
        if (line_idx > 0) line_idx -= 1;
        var line_start = @intCast(usize, offsets[@intCast(usize, line_idx)]);
        var line_end = content.len;
        var next_line = line_idx + 1;
        if (next_line < @intCast(u32, offsets.len)) {
            line_end = @intCast(usize, offsets[@intCast(usize, next_line)]);
            if (line_end > 0 and content[line_end - 1] == '\n') line_end -= 1;
        }
        var l_start = line_start;
        var l_end = line_end;
        if (l_start < l_end and l_end <= content.len) {
            var line_text = content[l_start..l_end];
            writeStr(line_text);
            var nl2: []const u8 = "\n";
            writeStr(nl2);
            var loc_col: usize = @intCast(usize, loc.col);
            var cspan: usize = @intCast(usize, d.span_end - d.span_start);
            if (cspan == 0) cspan = 1;
            var caret_buf: [256]u8 = undefined;
            var caret_len: usize = 0;
            var space_count = loc_col;
            if (space_count > 256) space_count = 256;
            for (0..space_count) |_| {
                caret_buf[caret_len] = ' ';
                caret_len += 1;
            }
            var ulen = cspan;
            if (ulen > 256 - loc_col) ulen = 256 - loc_col;
            var max_carets = ulen;
            if (max_carets > 256 - caret_len) max_carets = 256 - caret_len;
            for (0..max_carets) |_| {
                caret_buf[caret_len] = '^';
                caret_len += 1;
            }
            writeStr(caret_buf[0..caret_len]);
            var nl3: []const u8 = "\n";
            writeStr(nl3);
        }
        var n: u8 = 0;
        while (n < d.note_count) {
            var note_hdr: []const u8 = "note: ";
            writeStr(note_hdr);
            var note_entry = self.interner.entries_items[@intCast(usize, d.note_ids[@intCast(usize, n)])];
            writeStr(note_entry.text);
            var note_nl: []const u8 = "\n";
            writeStr(note_nl);
            n += 1;
        }
        if (d.related_span_idx > 0 and d.related_span_idx < @intCast(u16, self.related_span_len)) {
            var rs = self.related_span_items[@intCast(usize, d.related_span_idx)];
            var rs_loc = sm_mod.sourceManagerGetLocation(self.source_manager, rs.span_file_id, rs.span_start);
            var rs_fname = sm_mod.sourceManagerGetFileName(self.source_manager, rs.span_file_id);
            writeStr(rs_fname);
            var rs_col_s: []const u8 = ":";
            writeStr(rs_col_s);
            var rs_line_buf: [16]u8 = undefined;
            var rs_line_len = formatU32(rs_loc.line, rs_line_buf[0..16]);
            var rls: usize = @intCast(usize, 16) - @intCast(usize, rs_line_len);
            writeStr(rs_line_buf[rls..@intCast(usize, 16)]);
            var rs_sep: []const u8 = ": note: ";
            writeStr(rs_sep);
            var rs_msg = self.interner.entries_items[@intCast(usize, rs.message_id)];
            writeStr(rs_msg.text);
            var rs_nl: []const u8 = "\n";
            writeStr(rs_nl);
        }
        i += 1;
    }
    var pe: []const u8 = "PA_end\n"; pal.stderr_write(pe);
}
