const TokenKind = @import("../token.zig").TokenKind;
const Token = @import("../token.zig").Token;
const TokenValue = @import("../token.zig").TokenValue;
const ast_mod = @import("../ast.zig");
const AstStore = ast_mod.AstStore;
const AstKind = ast_mod.AstKind;
const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const parser_mod = @import("../parser.zig");
const pal = @import("../pal.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var buf: [32768]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var in_ = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var d = diag_mod.diagnosticCollectorInit(&a, &sm, &in_);
    var store = ast_mod.astStoreInit(&a);
    var x_s: []const u8 = "x"; var y_s: []const u8 = "y";
    var xi = interner_mod.stringInternerIntern(&in_, x_s);
    var yi = interner_mod.stringInternerIntern(&in_, y_s);
    var tk: [10]Token = undefined;
    tk[0] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 0), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[1] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 6), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = xi } };
    tk[2] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 8), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[3] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 10), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 42) } };
    tk[4] = Token{ .kind = TokenKind.kw_const, .span_start = @intCast(u32, 13), .span_len = @intCast(u16, 5), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[5] = Token{ .kind = TokenKind.identifier, .span_start = @intCast(u32, 19), .span_len = @intCast(u16, 1), .value = TokenValue{ .string_id = yi } };
    tk[6] = Token{ .kind = TokenKind.eq, .span_start = @intCast(u32, 21), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[7] = Token{ .kind = TokenKind.integer_literal, .span_start = @intCast(u32, 23), .span_len = @intCast(u16, 2), .value = TokenValue{ .int_val = @intCast(u64, 99) } };
    tk[8] = Token{ .kind = TokenKind.semicolon, .span_start = @intCast(u32, 25), .span_len = @intCast(u16, 1), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    tk[9] = Token{ .kind = TokenKind.eof, .span_start = @intCast(u32, 26), .span_len = @intCast(u16, 0), .value = TokenValue{ .int_val = @intCast(u64, 0) } };
    var ss: []const u8 = "const x = 42 const y = 99;";
    var p = parser_mod.parserInit(tk[0..], ss, &store, &in_, &d, &a);
    var root = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    var node = store.nodes.items[root];
    var child_count = @intCast(u32, node.payload & 0xFFFF);
    var ok_msg: []const u8 = "OK count=";
    pal.stderr_write(ok_msg);
    var nc: [4]u8 = undefined;
    var v = child_count;
    var dc: usize = 0;
    while (dc < 4) { nc[dc] = @intCast(u8, 48 + v % 10); dc += 1; v = v / 10; }
    pal.stderr_write(nc[dc-3..dc+1]);
    pal.stderr_write("\n");
    var ec = ast_mod.astStoreGetExtraChildren(&store, node.payload);
    var ds: []const u8 = "ec_len=";
    pal.stderr_write(ds);
    var el: [4]u8 = undefined;
    v = @intCast(u32, ec.len);
    dc = 0;
    while (dc < 4) { el[dc] = @intCast(u8, 48 + v % 10); dc += 1; v = v / 10; }
    pal.stderr_write(el[dc-3..dc+1]);
    pal.stderr_write("\n");
    var i: usize = 0;
    while (i < ec.len) {
        var ci = ec[i];
        var ckind = @enumToInt(store.nodes.items[ci].kind);
        var ml: []const u8 = "  kind=";
        pal.stderr_write(ml);
        var bk: [4]u8 = undefined;
        var v2 = @intCast(u32, ckind);
        dc = 0;
        while (dc < 4) { bk[dc] = @intCast(u8, 48 + v2 % 10); dc += 1; v2 = v2 / 10; }
        pal.stderr_write(bk[dc-3..dc+1]);
        pal.stderr_write("\n");
        i += 1;
    }
}
