const TokenKind = @import("../token.zig").TokenKind;
const parser_mod = @import("../parser.zig");
fn assertEqU32(actual: u32, expected: u32) void {
    if (actual != expected) @panic("assertEqU32 failed");
}

pub fn runParserUnitTests() void {
    testPrecEnumValues();
    testPrecToInt();
    testPrecFromInt();
    testGetInfixInfoReturnsAssignment();
    testGetInfixInfoReturnsNull();
    testGetInfixInfoReturnsRightAssoc();
}

fn testPrecEnumValues() void {
    assertEqU32(@intCast(u32, @enumToInt(Prec.none)), @intCast(u32, 0));
    assertEqU32(@intCast(u32, @enumToInt(Prec.assignment)), @intCast(u32, 1));
    assertEqU32(@intCast(u32, @enumToInt(Prec.multiply)), @intCast(u32, 12));
    assertEqU32(@intCast(u32, @enumToInt(Prec.prefix)), @intCast(u32, 13));
}

fn testPrecToInt() void {
    assertEqU32(@intCast(u32, parser_mod.precToInt(Prec.none)), @intCast(u32, 0));
    assertEqU32(@intCast(u32, parser_mod.precToInt(Prec.assignment)), @intCast(u32, 1));
    assertEqU32(@intCast(u32, parser_mod.precToInt(Prec.multiply)), @intCast(u32, 12));
}

fn testPrecFromInt() void {
    assertEqU32(@intCast(u32, @enumToInt(parser_mod.precFromInt(@intCast(u8, 0)))), @intCast(u32, 0));
    assertEqU32(@intCast(u32, @enumToInt(parser_mod.precFromInt(@intCast(u8, 1)))), @intCast(u32, 1));
    assertEqU32(@intCast(u32, @enumToInt(parser_mod.precFromInt(@intCast(u8, 12)))), @intCast(u32, 12));
}

const Prec = parser_mod.Prec;
const OpInfo = parser_mod.OpInfo;

fn testGetInfixInfoReturnsAssignment() void {
    var info = parser_mod.getInfixInfo(TokenKind.eq);
    if (info == null) {
        @panic("getInfixInfo(eq) should not be null");
    }
}

fn testGetInfixInfoReturnsNull() void {
    if (!(parser_mod.getInfixInfo(TokenKind.semicolon) == null)) {
        @panic("getInfixInfo(semicolon) should be null");
    }
}

fn testGetInfixInfoReturnsRightAssoc() void {
    var info = parser_mod.getInfixInfo(TokenKind.kw_orelse);
    if (info == null) {
        @panic("getInfixInfo(orelse) should not be null");
    }
}
