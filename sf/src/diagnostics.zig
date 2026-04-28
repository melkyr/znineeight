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
    ERR_3000_TYPE_MISMATCH,
    ERR_3001_UNDEFINED_SYMBOL,
    ERR_3002_INVALID_ASSIGNMENT,
    ERR_3003_MISSING_RETURN,
    ERR_3004_SWITCH_NOT_EXHAUSTIVE,
    ERR_3005_CIRCULAR_TYPE_DEPENDENCY,
    ERR_3006_INVALID_COERCION,
    WARN_3010_UNUSED_VARIABLE,
    WARN_3011_UNREACHABLE_CODE,
    ERR_4000_INVALID_CONTROL_FLOW,
    ERR_4001_UNRESOLVED_TYPE_IN_LOWER,
    ERR_4002_DEFER_IN_INVALID_SCOPE,
    ERR_5000_C89_UNSUPPORTED_FEATURE,
    ERR_5001_MANGLE_OVERFLOW,
    ERR_5002_EMPTY_AGGREGATE,
    ERR_9000_OOM,
    ERR_9001_ICE,
    ERR_9999_TOO_MANY_ERRORS,
};

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
        0 => return "error",
        1 => return "warning",
        2 => return "info",
        3 => return "note",
        else => return "unknown",
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
    var raw = alloc_mod.sandAlloc(self.allocator, @intCast(usize, 36) * new_cap, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]Diagnostic, raw);
    var i: usize = 0;
    while (i < self.len) {
        new_items[i] = self.items[i];
        i += 1;
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

pub fn diagnosticCollectorAdd(self: *DiagnosticCollector, level: u8, code: u16, file_id: u32, span_start: u32, span_end: u32, message: []const u8) void {
    if (code == 9999) return;
    if (self.diagnostics.len >= self.max_diagnostics) {
        var msg_id = interner_mod.stringInternerIntern(self.interner, "too many errors, stopping");
        diagnosticArrayListAppend(self.diagnostics, Diagnostic{
            .level = @intCast(u8, 0),
            .code = @intCast(u16, 9999),
            .file_id = file_id,
            .span_start = span_start,
            .span_end = span_end,
            .message_id = msg_id,
            .note_count = @intCast(u8, 0),
            .note_ids = [3]u32{ @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0) },
        });
        self.error_count += 1;
        return;
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
    });
    if (level == 0) self.error_count += 1;
    else if (level == 1) self.warning_count += 1;
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

pub fn diagnosticCollectorPrintAll(self: *DiagnosticCollector) void {
    if (self.diagnostics.len == 0) return;
    var diags = diagnosticArrayListGetSlice(self.diagnostics);
    sortDiagnostics(diags);
    var i: usize = 0;
    while (i < self.diagnostics.len) {
        var d = &diags[i];
        var loc = sm_mod.sourceManagerGetLocation(self.source_manager, d.file_id, d.span_start);
        var fname = sm_mod.sourceManagerGetFileName(self.source_manager, d.file_id);
        writeStr(fname);
        writeStr(":");
        var line_buf: [16]u8 = undefined;
        var line_len = formatU32(loc.line, &line_buf);
        writeStr(line_buf[0..@intCast(usize, line_len)]);
        writeStr(":");
        var col_buf: [16]u8 = undefined;
        var col_len = formatU32(loc.col, &col_buf);
        writeStr(col_buf[0..@intCast(usize, col_len)]);
        writeStr(": ");
        writeStr(getLevelName(d.level));
        writeStr("[");
        var code_buf: [8]u8 = undefined;
        var code_len = formatU32(d.code, &code_buf);
        writeStr(code_buf[0..@intCast(usize, code_len)]);
        writeStr("]: ");
        var entry = self.interner.entries.items[@intCast(usize, d.message_id)];
        writeStr(entry.text);
        writeStr("\n");
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
            writeStr("\n");
            var loc_col: usize = @intCast(usize, loc.col);
            var cspan: usize = @intCast(usize, d.span_end - d.span_start);
            if (cspan == 0) cspan = 1;
            var caret_buf: [256]u8 = undefined;
            var caret_len: usize = 0;
            while (caret_len < loc_col and caret_len < 256) {
                caret_buf[caret_len] = ' ';
                caret_len += 1;
            }
            var ulen = cspan;
            if (ulen > 256 - loc_col) ulen = 256 - loc_col;
            var j: usize = 0;
            while (j < ulen and caret_len < 256) {
                caret_buf[caret_len] = '^';
                caret_len += 1;
                j += 1;
            }
            writeStr(caret_buf[0..caret_len]);
            writeStr("\n");
        }
        i += 1;
    }
}
