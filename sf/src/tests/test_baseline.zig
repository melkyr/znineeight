const TokenKind = @import("../token.zig").TokenKind;
const Token = @import("../token.zig").Token;
const TokenValue = @import("../token.zig").TokenValue;
const ast_mod = @import("../ast.zig");
const AstKind = ast_mod.AstKind;
const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const parser_mod = @import("../parser.zig");

pub fn main() void {
    var buf: [65536]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var x_s: []const u8 = "x";
    var y_s: []const u8 = "y";
    var xi = interner_mod.stringInternerIntern(&in_, x_s);
    var yi = interner_mod.stringInternerIntern(&in_, y_s);
    var tk: [11]Token = undefined;
    tk[0] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[1] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = xi } };
    tk[2] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[3] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 10), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 42) } };
    tk[4] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 12), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[5] = Token{ .kind = TokenKind.kw_var, .span_start = @intCast(u32, 14), .span_len = @intCast(u16, 3), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[6] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 18), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = yi } };
    tk[7] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 20), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[8] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 22), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 99) } };
    tk[9] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 24), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[10] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 26), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var src_s: []const u8 = "const x = 42; var y = 99;";
    var p = parser_mod.parserInit(tk[0..], src_s, &store, &in_, &d, &a);
    var root = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[root];
    var ec = ast_mod.astStoreGetExtraChildren(&store, node.payload);
    var count: u32 = 0;
    var i: usize = 0;
    while (i < ec.len) {
        var child = store.nodes.items[ec[i]];
        if (@enumToInt(child.kind) == @enumToInt(AstKind.err)) count += 1;
        i += 1;
    }
    if (count != 0) @panic("baseline had errors");
}
