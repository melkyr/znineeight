const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const diag_mod = @import("diagnostics.zig");
const ast_mod = @import("ast.zig");
const StringInterner = @import("string_interner.zig").StringInterner;
const interner_mod = @import("string_interner.zig");

pub const PrintDecompEntry = struct {
    fmt_node_idx: u32,
    spec_count: u8,
};

fn printDecompScanFormat(fmt: []const u8) u8 {
    var count: u8 = 0;
    var i: usize = 0;
    while (i < fmt.len) : (i += 1) {
        if (fmt[i] == '{') {
            if (i + 1 < fmt.len and fmt[i + 1] == '{') {
                i += 1;
            } else if (i + 1 < fmt.len and fmt[i + 1] == '}') {
                count += 1;
                i += 1;
            } else {
            }
        } else if (fmt[i] == '}') {
            if (i + 1 < fmt.len and fmt[i + 1] == '}') {
                i += 1;
            } else {
            }
        } else {
        }
    }
    return count;
}

pub fn printDecompParseAndValidate(store: *AstStore, interner: *StringInterner, diag: *DiagnosticCollector, node_idx: u32) ?PrintDecompEntry {
    if (node_idx == @intCast(u32, 0)) return null;
    var node = store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind != AstKind.fn_call) return null;
    var args = ast_mod.astStoreGetExtraChildren(store, node.payload);
    if (args.len != @intCast(usize, 2)) return null;
    var fmt_node = store.nodes.items[@intCast(usize, args[0])];
    if (fmt_node.kind != AstKind.string_literal) return null;
    var raw = interner_mod.stringInternerGet(interner, fmt_node.payload);
    var spec_count = printDecompScanFormat(raw);
    var tup_node = store.nodes.items[@intCast(usize, args[1])];
    if (tup_node.kind != AstKind.tuple_literal) return null;
    var fields = ast_mod.astStoreGetExtraChildren(store, tup_node.payload);
    var fcount: u8 = @intCast(u8, fields.len);
    if (spec_count != fcount) {
        var fmsg: []const u8 = "format string argument count mismatch";
        diag_mod.diagnosticCollectorAdd(diag, @intCast(u8, 1), @intCast(u16, 0),
            @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), fmsg);
        return null;
    }
    return PrintDecompEntry{ .fmt_node_idx = args[0], .spec_count = spec_count };
}
