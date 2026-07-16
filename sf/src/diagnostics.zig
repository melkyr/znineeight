const type_mod = @import("type_registry.zig");

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
    ERR_3020_UNHANDLED_NODE_KIND = 3020,
    WARN_3010_UNUSED_VARIABLE,
    WARN_3011_UNREACHABLE_CODE,
    WARN_3012_MODULE_AS_VALUE,
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

pub fn diagnosticBuilderMakeMsg(interner: *StringInterner, parts: [*]const []const u8, count: u32) []const u8 {
    var total: usize = 0;
    var ci: u32 = 0;
    while (ci < count) : (ci += 1) { total += parts[@intCast(usize, ci)].len; }
    var raw = alloc_mod.sandAlloc(interner.allocator, total, 1) catch {
        var fallback: []const u8 = "diagnostic message too long";
        return fallback;
    };
    var buf = raw[0..total];
    var pos: usize = 0;
    ci = 0;
    while (ci < count) : (ci += 1) {
        var part = parts[@intCast(usize, ci)];
        var pi: usize = 0;
        while (pi < part.len) : (pi += 1) { buf[pos] = part[pi]; pos += 1; }
    }
    var sid = interner_mod.stringInternerIntern(interner, buf);
    return interner_mod.stringInternerGet(interner, sid);
}
pub fn diagnosticCollectorPrintAll(self: *DiagnosticCollector) void {
    if (self.diagnostics.len == 0) return;

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
 
}

pub fn typeKindSrcStr(kind: type_mod.TypeKind) []const u8 {
    var s_void: []const u8 = "source: void";
    var s_bool: []const u8 = "source: bool";
    var s_ctl: []const u8 = "source: comptime_int";
    var s_i8: []const u8 = "source: i8";
    var s_i16: []const u8 = "source: i16";
    var s_i32: []const u8 = "source: i32";
    var s_i64: []const u8 = "source: i64";
    var s_u8_: []const u8 = "source: u8";
    var s_u16: []const u8 = "source: u16";
    var s_u32: []const u8 = "source: u32";
    var s_u64: []const u8 = "source: u64";
    var s_f32: []const u8 = "source: f32";
    var s_f64: []const u8 = "source: f64";
    var s_ptr: []const u8 = "source: pointer";
    var s_mptr: []const u8 = "source: many-pointer";
    var s_slice: []const u8 = "source: slice";
    var s_opt: []const u8 = "source: optional";
    var s_eu: []const u8 = "source: error-union";
    var s_es: []const u8 = "source: error-set";
    var s_arr: []const u8 = "source: array";
    var s_struct: []const u8 = "source: struct";
    var s_enum: []const u8 = "source: enum";
    var s_union: []const u8 = "source: union";
    var s_tu: []const u8 = "source: tagged-union";
    var s_fn: []const u8 = "source: function";
    var s_tuple: []const u8 = "source: tuple";
    var s_null: []const u8 = "source: null";
    var s_nr: []const u8 = "source: noreturn";
    var s_type: []const u8 = "source: type";
    if (kind == type_mod.TypeKind.void_type) { return s_void; }
    if (kind == type_mod.TypeKind.bool_type) { return s_bool; }
    if (kind == type_mod.TypeKind.integer_literal_type) { return s_ctl; }
    if (kind == type_mod.TypeKind.i8_type) { return s_i8; }
    if (kind == type_mod.TypeKind.i16_type) { return s_i16; }
    if (kind == type_mod.TypeKind.i32_type) { return s_i32; }
    if (kind == type_mod.TypeKind.i64_type) { return s_i64; }
    if (kind == type_mod.TypeKind.u8_type) { return s_u8_; }
    if (kind == type_mod.TypeKind.u16_type) { return s_u16; }
    if (kind == type_mod.TypeKind.u32_type) { return s_u32; }
    if (kind == type_mod.TypeKind.u64_type) { return s_u64; }
    if (kind == type_mod.TypeKind.f32_type) { return s_f32; }
    if (kind == type_mod.TypeKind.f64_type) { return s_f64; }
    if (kind == type_mod.TypeKind.ptr_type) { return s_ptr; }
    if (kind == type_mod.TypeKind.many_ptr_type) { return s_mptr; }
    if (kind == type_mod.TypeKind.slice_type) { return s_slice; }
    if (kind == type_mod.TypeKind.optional_type) { return s_opt; }
    if (kind == type_mod.TypeKind.error_union_type) { return s_eu; }
    if (kind == type_mod.TypeKind.error_set_type) { return s_es; }
    if (kind == type_mod.TypeKind.array_type) { return s_arr; }
    if (kind == type_mod.TypeKind.struct_type) { return s_struct; }
    if (kind == type_mod.TypeKind.enum_type) { return s_enum; }
    if (kind == type_mod.TypeKind.union_type) { return s_union; }
    if (kind == type_mod.TypeKind.tagged_union_type) { return s_tu; }
    if (kind == type_mod.TypeKind.fn_type) { return s_fn; }
    if (kind == type_mod.TypeKind.tuple_type) { return s_tuple; }
    if (kind == type_mod.TypeKind.null_type) { return s_null; }
    if (kind == type_mod.TypeKind.noreturn_type) { return s_nr; }
    return s_type;
}

pub fn typeKindTgtStr(kind: type_mod.TypeKind) []const u8 {
    var s_void: []const u8 = "target: void";
    var s_bool: []const u8 = "target: bool";
    var s_ctl: []const u8 = "target: comptime_int";
    var s_i8: []const u8 = "target: i8";
    var s_i16: []const u8 = "target: i16";
    var s_i32: []const u8 = "target: i32";
    var s_i64: []const u8 = "target: i64";
    var s_u8_: []const u8 = "target: u8";
    var s_u16: []const u8 = "target: u16";
    var s_u32: []const u8 = "target: u32";
    var s_u64: []const u8 = "target: u64";
    var s_f32: []const u8 = "target: f32";
    var s_f64: []const u8 = "target: f64";
    var s_ptr: []const u8 = "target: pointer";
    var s_mptr: []const u8 = "target: many-pointer";
    var s_slice: []const u8 = "target: slice";
    var s_opt: []const u8 = "target: optional";
    var s_eu: []const u8 = "target: error-union";
    var s_es: []const u8 = "target: error-set";
    var s_arr: []const u8 = "target: array";
    var s_struct: []const u8 = "target: struct";
    var s_enum: []const u8 = "target: enum";
    var s_union: []const u8 = "target: union";
    var s_tu: []const u8 = "target: tagged-union";
    var s_fn: []const u8 = "target: function";
    var s_tuple: []const u8 = "target: tuple";
    var s_null: []const u8 = "target: null";
    var s_nr: []const u8 = "target: noreturn";
    var s_type: []const u8 = "target: type";
    if (kind == type_mod.TypeKind.void_type) { return s_void; }
    if (kind == type_mod.TypeKind.bool_type) { return s_bool; }
    if (kind == type_mod.TypeKind.integer_literal_type) { return s_ctl; }
    if (kind == type_mod.TypeKind.i8_type) { return s_i8; }
    if (kind == type_mod.TypeKind.i16_type) { return s_i16; }
    if (kind == type_mod.TypeKind.i32_type) { return s_i32; }
    if (kind == type_mod.TypeKind.i64_type) { return s_i64; }
    if (kind == type_mod.TypeKind.u8_type) { return s_u8_; }
    if (kind == type_mod.TypeKind.u16_type) { return s_u16; }
    if (kind == type_mod.TypeKind.u32_type) { return s_u32; }
    if (kind == type_mod.TypeKind.u64_type) { return s_u64; }
    if (kind == type_mod.TypeKind.f32_type) { return s_f32; }
    if (kind == type_mod.TypeKind.f64_type) { return s_f64; }
    if (kind == type_mod.TypeKind.ptr_type) { return s_ptr; }
    if (kind == type_mod.TypeKind.many_ptr_type) { return s_mptr; }
    if (kind == type_mod.TypeKind.slice_type) { return s_slice; }
    if (kind == type_mod.TypeKind.optional_type) { return s_opt; }
    if (kind == type_mod.TypeKind.error_union_type) { return s_eu; }
    if (kind == type_mod.TypeKind.error_set_type) { return s_es; }
    if (kind == type_mod.TypeKind.array_type) { return s_arr; }
    if (kind == type_mod.TypeKind.struct_type) { return s_struct; }
    if (kind == type_mod.TypeKind.enum_type) { return s_enum; }
    if (kind == type_mod.TypeKind.union_type) { return s_union; }
    if (kind == type_mod.TypeKind.tagged_union_type) { return s_tu; }
    if (kind == type_mod.TypeKind.fn_type) { return s_fn; }
    if (kind == type_mod.TypeKind.tuple_type) { return s_tuple; }
    if (kind == type_mod.TypeKind.null_type) { return s_null; }
    if (kind == type_mod.TypeKind.noreturn_type) { return s_nr; }
    return s_type;
}
