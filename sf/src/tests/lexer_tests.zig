const pal = @import("../pal.zig");
const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const mem_mod = @import("../util/mem.zig");
const sm_mod = @import("../source_manager.zig");
const SourceManager = sm_mod.SourceManager;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const token_mod = @import("../token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const TokenValue = token_mod.TokenValue;
const lexer_mod = @import("../lexer.zig");
const Lexer = lexer_mod.Lexer;

var arena_buf: [32768]u8 = undefined;
var sand: Sand = undefined;
var interner: StringInterner = undefined;
var source_man: SourceManager = undefined;
var diag: DiagnosticCollector = undefined;

fn initTestHarness() void {
    sand = alloc_mod.sandInit(arena_buf[0..]);
    interner = interner_mod.stringInternerInit(&sand, 4);
    source_man = sm_mod.sourceManagerInit(&sand);
    diag = diag_mod.diagnosticCollectorInit(&sand, &source_man, &interner);
}

fn makeLexer(src: []const u8) Lexer {
    return lexer_mod.lexerInit(src, 0, &interner, &diag, &sand);
}

fn assertEqU64(expected: u64, actual: u64, line: u32) void {
    if (expected != actual) {
        var fmt_buf: [24]u8 = undefined;
        const s_fail: []const u8 = "FAIL line ";
        pal.stderr_write(s_fail);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 24));
        const s_sp: []const u8 = " ";
        pal.stderr_write(s_sp);
        pal.stderr_write(formatU64(expected, fmt_buf[0..], 24));
        const s_got: []const u8 = " != ";
        pal.stderr_write(s_got);
        pal.stderr_write(formatU64(actual, fmt_buf[0..], 24));
        const s_nl: []const u8 = "\n";
        pal.stderr_write(s_nl);
    }
}

fn assertEqString(expected: []const u8, actual_id: u32, line: u32) void {
    if (!mem_mod.mem_eql(expected, interner_mod.stringInternerGet(&interner, actual_id))) {
        var fmt_buf: [24]u8 = undefined;
        const s_fail: []const u8 = "FAIL line ";
        pal.stderr_write(s_fail);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 12));
        const s_msg: []const u8 = ": string mismatch\n";
        pal.stderr_write(s_msg);
    }
}

fn formatU64(val: u64, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, v % 10));
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len];
}

fn assertEqTokenKind(tk: TokenKind, expected: TokenKind, line: u32) void {
    if (tk != expected) {
        var fmt_buf: [24]u8 = undefined;
        const s_fail: []const u8 = "FAIL line ";
        pal.stderr_write(s_fail);
        pal.stderr_write(formatU32(line, fmt_buf[0..], 12));
        const s_msg: []const u8 = ": token kind mismatch\n";
        pal.stderr_write(s_msg);
    }
}

fn formatU32(val: u32, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + v % 10);
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len];
}

fn nextKind(l: *Lexer) TokenKind {
    return lexer_mod.lexerNextToken(l).kind;
}

fn nextToken(l: *Lexer) Token {
    return lexer_mod.lexerNextToken(l);
}

pub fn runLexerUnitTests() void {
    initTestHarness();
    testIntegerOverflow();
    initTestHarness();
    testFloatBasic();
    initTestHarness();
    testFloatScientific();
    initTestHarness();
    testFloatNoFrac();
    initTestHarness();
    testShiftOps();
    initTestHarness();
    testFatArrow();
    initTestHarness();
    testEqVariants();
    initTestHarness();
    testBuiltinImport();
    initTestHarness();
    testBareAt();
    initTestHarness();
    testBareUnderscore();
    initTestHarness();
    testUnderscoreIdent();
    initTestHarness();
    testWhitespaceOnly();
    initTestHarness();
    testNestedComment();
    initTestHarness();
    testUnterminatedComment();
    initTestHarness();
    testStringBasic();
    initTestHarness();
    testCharEmpty();
    initTestHarness();
    testStringUnterminated();
    initTestHarness();
    testStringEscapeHex();
    initTestHarness();
    testBlockComments();
    initTestHarness();
    testLineComments();
    initTestHarness();
    testNumberSeparators();
    initTestHarness();
    testIntegerEdgeCases();
    initTestHarness();
    testFloatEdgeCases();
    initTestHarness();
    testStringEscapeSequences();
    initTestHarness();
    testCharEscapeSequences();
    initTestHarness();
    testEofBoundary();
    initTestHarness();
    testAllKeywords();
    initTestHarness();
    testDotVariants();
    initTestHarness();
    testMultiTokenRecovery();
    initTestHarness();
    testUnrecognizedChars();
    initTestHarness();
    testSwitchMultiProng();
    initTestHarness();
    testSwitchCapture();
    initTestHarness();
    testTryExpr();
    initTestHarness();
    testErrorLiteral();
    initTestHarness();
    testNestedSwitch();
    initTestHarness();
    testIfExpr();
    initTestHarness();
    testBuiltinCast();
    initTestHarness();
    testSliceSyntax();
    initTestHarness();
    testOptionalCapture();
    initTestHarness();
    testDerefField();
    initTestHarness();
    testIntegrationMandelbrot();
    initTestHarness();
    testIntegrationGameOfLife();
    initTestHarness();
    testIntegrationMud();
}

fn testIntegerOverflow() void {
    const s: []const u8 = "99999999999999999999";
    var l = makeLexer(s);
    var t = nextToken(&l);
    assertEqTokenKind(t.kind, TokenKind.integer_literal, @intCast(u32, 0));
    var expected_max: u64 = 0;
    expected_max -= 1;
    assertEqU64(expected_max, t.value.int_val, @intCast(u32, 0));
}

fn testFloatBasic() void {
    const s: []const u8 = "3.14";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 0));
}

fn testFloatScientific() void {
    const s: []const u8 = "1.0e-5";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 0));
}

fn testFloatNoFrac() void {
    const s: []const u8 = "2.0";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 0));
}

fn testShiftOps() void {
    const s: []const u8 = "<< >> <<= >>=";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.shl, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.shr, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.shl_eq, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.shr_eq, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));
}

fn testFatArrow() void {
    const s: []const u8 = "=>";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));
}

fn testEqVariants() void {
    const s: []const u8 = "= == =>";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.eq_eq, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));
}

fn testBuiltinImport() void {
    const s: []const u8 = "@import";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.builtin_identifier, @intCast(u32, 0));
}

fn testBareAt() void {
    const s: []const u8 = "@+";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.err_token, @intCast(u32, 0));
}

fn testBareUnderscore() void {
    const s: []const u8 = "_";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.underscore, @intCast(u32, 0));
}

fn testUnderscoreIdent() void {
    const s: []const u8 = "_foo";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 0));
}

fn testWhitespaceOnly() void {
    const s: []const u8 = "   \t\n  ";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));
}

fn testNestedComment() void {
    const s: []const u8 = "42 /* a /* b */ c */ 43";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));
}

fn testUnterminatedComment() void {
    const s: []const u8 = "42 /* no close";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));
}

fn testStringBasic() void {
    const s: []const u8 = "\"hello\"";
    var l = makeLexer(s);
    var t = nextToken(&l);
    assertEqTokenKind(t.kind, TokenKind.string_literal, @intCast(u32, 0));
    const expected: []const u8 = "hello";
    assertEqString(expected, t.value.string_id, @intCast(u32, 0));
}

fn testCharEmpty() void {
    const s: []const u8 = "''";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.char_literal, @intCast(u32, 0));
}

fn testStringUnterminated() void {
    const s: []const u8 = "\"hello";
    var l = makeLexer(s);
    var t = nextToken(&l);
    assertEqTokenKind(t.kind, TokenKind.string_literal, @intCast(u32, 0));
}

fn testStringEscapeHex() void {
    const s: []const u8 = "\"\\xFF\"";
    var l = makeLexer(s);
    var t = nextToken(&l);
    assertEqTokenKind(t.kind, TokenKind.string_literal, @intCast(u32, 0));
    var got = interner_mod.stringInternerGet(&interner, t.value.string_id);
    if (got.len != 1 or got[0] != @intCast(u8, 0xFF)) {
        const s_fail: []const u8 = "FAIL: string \\xFF content\n";
        pal.stderr_write(s_fail);
    }
}

fn testBlockComments() void {
    const s: []const u8 = "/* comment */42";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));

    const s2: []const u8 = "/* outer /* inner */ */99";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.integer_literal, @intCast(u32, 0));

    const s3: []const u8 = "42/* comment */";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l3), TokenKind.eof, @intCast(u32, 0));

    const s4: []const u8 = "/*";
    var l4 = makeLexer(s4);
    assertEqTokenKind(nextKind(&l4), TokenKind.eof, @intCast(u32, 0));
}

fn testLineComments() void {
    const s: []const u8 = "// line comment\n99";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));

    const s2: []const u8 = "99 // trailing comment";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l2), TokenKind.eof, @intCast(u32, 0));

    const s3: []const u8 = "// comment at eof";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.eof, @intCast(u32, 0));
}

fn testNumberSeparators() void {
    const s: []const u8 = "1_000_000";
    var l = makeLexer(s);
    var t = nextToken(&l);
    assertEqTokenKind(t.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(1000000, t.value.int_val, @intCast(u32, 0));

    const s2: []const u8 = "0xFFFF_FFFF";
    var l2 = makeLexer(s2);
    var t2 = nextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(0xFFFFFFFF, t2.value.int_val, @intCast(u32, 0));

    const s3: []const u8 = "0b1010_0101";
    var l3 = makeLexer(s3);
    var t3 = nextToken(&l3);
    assertEqTokenKind(t3.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(0xA5, t3.value.int_val, @intCast(u32, 0));

    const s4: []const u8 = "0o77_00";
    var l4 = makeLexer(s4);
    var t4 = nextToken(&l4);
    assertEqTokenKind(t4.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(4032, t4.value.int_val, @intCast(u32, 0));

    const s5: []const u8 = "3.141_59";
    var l5 = makeLexer(s5);
    assertEqTokenKind(nextKind(&l5), TokenKind.float_literal, @intCast(u32, 0));
}

fn testIntegerEdgeCases() void {
    const s: []const u8 = "0";
    var l = makeLexer(s);
    var t = nextToken(&l);
    assertEqTokenKind(t.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(0, t.value.int_val, @intCast(u32, 0));

    const s2: []const u8 = "18446744073709551615";
    var l2 = makeLexer(s2);
    var t2 = nextToken(&l2);
    assertEqTokenKind(t2.kind, TokenKind.integer_literal, @intCast(u32, 0));
    var expected_max: u64 = 0;
    expected_max -= 1;
    assertEqU64(expected_max, t2.value.int_val, @intCast(u32, 0));

    const s3: []const u8 = "0x0";
    var l3 = makeLexer(s3);
    var t3 = nextToken(&l3);
    assertEqTokenKind(t3.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(0, t3.value.int_val, @intCast(u32, 0));

    const s4: []const u8 = "0b0";
    var l4 = makeLexer(s4);
    var t4 = nextToken(&l4);
    assertEqTokenKind(t4.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(0, t4.value.int_val, @intCast(u32, 0));

    const s5: []const u8 = "0o0";
    var l5 = makeLexer(s5);
    var t5 = nextToken(&l5);
    assertEqTokenKind(t5.kind, TokenKind.integer_literal, @intCast(u32, 0));
    assertEqU64(0, t5.value.int_val, @intCast(u32, 0));
}

fn testFloatEdgeCases() void {
    const s: []const u8 = "1e10";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 0));

    const s2: []const u8 = "1e-10";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.float_literal, @intCast(u32, 0));

    const s3: []const u8 = "1.0e10";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.float_literal, @intCast(u32, 0));

    const s4: []const u8 = "0..10";
    var l4 = makeLexer(s4);
    assertEqTokenKind(nextKind(&l4), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l4), TokenKind.dot_dot, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l4), TokenKind.integer_literal, @intCast(u32, 0));

    const s5: []const u8 = "0.0";
    var l5 = makeLexer(s5);
    assertEqTokenKind(nextKind(&l5), TokenKind.float_literal, @intCast(u32, 0));

    const s6: []const u8 = "3.0e+5";
    var l6 = makeLexer(s6);
    assertEqTokenKind(nextKind(&l6), TokenKind.float_literal, @intCast(u32, 0));
}

fn testStringEscapeSequences() void {
    const s: []const u8 = "\"\\n\"";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.string_literal, @intCast(u32, 0));

    const s2: []const u8 = "\"\\t\"";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.string_literal, @intCast(u32, 0));

    const s3: []const u8 = "\"\\r\"";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.string_literal, @intCast(u32, 0));

    const s4: []const u8 = "\"\\\\\"";
    var l4 = makeLexer(s4);
    assertEqTokenKind(nextKind(&l4), TokenKind.string_literal, @intCast(u32, 0));

    const s5: []const u8 = "\"\\\"\"";
    var l5 = makeLexer(s5);
    assertEqTokenKind(nextKind(&l5), TokenKind.string_literal, @intCast(u32, 0));

    const s6: []const u8 = "\"\\0\"";
    var l6 = makeLexer(s6);
    assertEqTokenKind(nextKind(&l6), TokenKind.string_literal, @intCast(u32, 0));

    const s7: []const u8 = "\"\\x41\"";
    var l7 = makeLexer(s7);
    assertEqTokenKind(nextKind(&l7), TokenKind.string_literal, @intCast(u32, 0));

    const s8: []const u8 = "\"\\x\"";
    var l8 = makeLexer(s8);
    assertEqTokenKind(nextKind(&l8), TokenKind.string_literal, @intCast(u32, 0));

    const s9: []const u8 = "\"\\z\"";
    var l9 = makeLexer(s9);
    assertEqTokenKind(nextKind(&l9), TokenKind.string_literal, @intCast(u32, 0));
}

fn testCharEscapeSequences() void {
    const s: []const u8 = "'\\n'";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.char_literal, @intCast(u32, 0));

    const s2: []const u8 = "'\\t'";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.char_literal, @intCast(u32, 0));

    const s3: []const u8 = "'\\r'";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.char_literal, @intCast(u32, 0));

    const s4: []const u8 = "'\\\\'";
    var l4 = makeLexer(s4);
    assertEqTokenKind(nextKind(&l4), TokenKind.char_literal, @intCast(u32, 0));

    const s5: []const u8 = "'\\\''";
    var l5 = makeLexer(s5);
    assertEqTokenKind(nextKind(&l5), TokenKind.char_literal, @intCast(u32, 0));

    const s6: []const u8 = "'\\0'";
    var l6 = makeLexer(s6);
    assertEqTokenKind(nextKind(&l6), TokenKind.char_literal, @intCast(u32, 0));

    const s7: []const u8 = "'\\x41'";
    var l7 = makeLexer(s7);
    assertEqTokenKind(nextKind(&l7), TokenKind.char_literal, @intCast(u32, 0));

    const s8: []const u8 = "'\\z'";
    var l8 = makeLexer(s8);
    assertEqTokenKind(nextKind(&l8), TokenKind.char_literal, @intCast(u32, 0));

    const s9: []const u8 = "'a'";
    var l9 = makeLexer(s9);
    var t9 = nextToken(&l9);
    assertEqTokenKind(t9.kind, TokenKind.char_literal, @intCast(u32, 0));
    assertEqU64('a', t9.value.int_val, @intCast(u32, 0));
}

fn testEofBoundary() void {
    const s: []const u8 = "";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 0));

    var l2 = makeLexer(s);
    assertEqTokenKind(nextKind(&l2), TokenKind.eof, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l2), TokenKind.eof, @intCast(u32, 0));

    const s3: []const u8 = "42";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l3), TokenKind.eof, @intCast(u32, 0));
}

fn testAllKeywords() void {
    const s_const: []const u8 = "const";
    var l1 = makeLexer(s_const);
    assertEqTokenKind(nextKind(&l1), TokenKind.kw_const, @intCast(u32, 1));

    const s_var: []const u8 = "var";
    var l2 = makeLexer(s_var);
    assertEqTokenKind(nextKind(&l2), TokenKind.kw_var, @intCast(u32, 2));

    const s_fn: []const u8 = "fn";
    var l3 = makeLexer(s_fn);
    assertEqTokenKind(nextKind(&l3), TokenKind.kw_fn, @intCast(u32, 3));

    const s_pub: []const u8 = "pub";
    var l4 = makeLexer(s_pub);
    assertEqTokenKind(nextKind(&l4), TokenKind.kw_pub, @intCast(u32, 4));

    const s_extern: []const u8 = "extern";
    var l5 = makeLexer(s_extern);
    assertEqTokenKind(nextKind(&l5), TokenKind.kw_extern, @intCast(u32, 5));

    const s_export: []const u8 = "export";
    var l6 = makeLexer(s_export);
    assertEqTokenKind(nextKind(&l6), TokenKind.kw_export, @intCast(u32, 6));

    const s_test: []const u8 = "test";
    var l7 = makeLexer(s_test);
    assertEqTokenKind(nextKind(&l7), TokenKind.kw_test, @intCast(u32, 7));

    const s_struct: []const u8 = "struct";
    var l8 = makeLexer(s_struct);
    assertEqTokenKind(nextKind(&l8), TokenKind.kw_struct, @intCast(u32, 8));

    const s_enum: []const u8 = "enum";
    var l9 = makeLexer(s_enum);
    assertEqTokenKind(nextKind(&l9), TokenKind.kw_enum, @intCast(u32, 9));

    const s_union: []const u8 = "union";
    var l10 = makeLexer(s_union);
    assertEqTokenKind(nextKind(&l10), TokenKind.kw_union, @intCast(u32, 10));

    const s_if: []const u8 = "if";
    var l11 = makeLexer(s_if);
    assertEqTokenKind(nextKind(&l11), TokenKind.kw_if, @intCast(u32, 11));

    const s_else: []const u8 = "else";
    var l12 = makeLexer(s_else);
    assertEqTokenKind(nextKind(&l12), TokenKind.kw_else, @intCast(u32, 12));

    const s_while: []const u8 = "while";
    var l13 = makeLexer(s_while);
    assertEqTokenKind(nextKind(&l13), TokenKind.kw_while, @intCast(u32, 13));

    const s_for: []const u8 = "for";
    var l14 = makeLexer(s_for);
    assertEqTokenKind(nextKind(&l14), TokenKind.kw_for, @intCast(u32, 14));

    const s_switch: []const u8 = "switch";
    var l15 = makeLexer(s_switch);
    assertEqTokenKind(nextKind(&l15), TokenKind.kw_switch, @intCast(u32, 15));

    const s_return: []const u8 = "return";
    var l16 = makeLexer(s_return);
    assertEqTokenKind(nextKind(&l16), TokenKind.kw_return, @intCast(u32, 16));

    const s_break: []const u8 = "break";
    var l17 = makeLexer(s_break);
    assertEqTokenKind(nextKind(&l17), TokenKind.kw_break, @intCast(u32, 17));

    const s_continue: []const u8 = "continue";
    var l18 = makeLexer(s_continue);
    assertEqTokenKind(nextKind(&l18), TokenKind.kw_continue, @intCast(u32, 18));

    const s_defer: []const u8 = "defer";
    var l19 = makeLexer(s_defer);
    assertEqTokenKind(nextKind(&l19), TokenKind.kw_defer, @intCast(u32, 19));

    const s_errdefer: []const u8 = "errdefer";
    var l20 = makeLexer(s_errdefer);
    assertEqTokenKind(nextKind(&l20), TokenKind.kw_errdefer, @intCast(u32, 20));

    const s_try: []const u8 = "try";
    var l21 = makeLexer(s_try);
    assertEqTokenKind(nextKind(&l21), TokenKind.kw_try, @intCast(u32, 21));

    const s_catch: []const u8 = "catch";
    var l22 = makeLexer(s_catch);
    assertEqTokenKind(nextKind(&l22), TokenKind.kw_catch, @intCast(u32, 22));

    const s_orelse: []const u8 = "orelse";
    var l23 = makeLexer(s_orelse);
    assertEqTokenKind(nextKind(&l23), TokenKind.kw_orelse, @intCast(u32, 23));

    const s_error: []const u8 = "error";
    var l24 = makeLexer(s_error);
    assertEqTokenKind(nextKind(&l24), TokenKind.kw_error, @intCast(u32, 24));

    const s_and: []const u8 = "and";
    var l25 = makeLexer(s_and);
    assertEqTokenKind(nextKind(&l25), TokenKind.kw_and, @intCast(u32, 25));

    const s_or: []const u8 = "or";
    var l26 = makeLexer(s_or);
    assertEqTokenKind(nextKind(&l26), TokenKind.kw_or, @intCast(u32, 26));

    const s_true: []const u8 = "true";
    var l27 = makeLexer(s_true);
    assertEqTokenKind(nextKind(&l27), TokenKind.kw_true, @intCast(u32, 27));

    const s_false: []const u8 = "false";
    var l28 = makeLexer(s_false);
    assertEqTokenKind(nextKind(&l28), TokenKind.kw_false, @intCast(u32, 28));

    const s_null: []const u8 = "null";
    var l29 = makeLexer(s_null);
    assertEqTokenKind(nextKind(&l29), TokenKind.kw_null, @intCast(u32, 29));

    const s_undefined: []const u8 = "undefined";
    var l30 = makeLexer(s_undefined);
    assertEqTokenKind(nextKind(&l30), TokenKind.kw_undefined, @intCast(u32, 30));

    const s_unreachable: []const u8 = "unreachable";
    var l31 = makeLexer(s_unreachable);
    assertEqTokenKind(nextKind(&l31), TokenKind.kw_unreachable, @intCast(u32, 31));

    const s_void: []const u8 = "void";
    var l32 = makeLexer(s_void);
    assertEqTokenKind(nextKind(&l32), TokenKind.kw_void, @intCast(u32, 32));

    const s_bool: []const u8 = "bool";
    var l33 = makeLexer(s_bool);
    assertEqTokenKind(nextKind(&l33), TokenKind.kw_bool, @intCast(u32, 33));

    const s_noreturn: []const u8 = "noreturn";
    var l34 = makeLexer(s_noreturn);
    assertEqTokenKind(nextKind(&l34), TokenKind.kw_noreturn, @intCast(u32, 34));

    const s_c_char: []const u8 = "c_char";
    var l35 = makeLexer(s_c_char);
    assertEqTokenKind(nextKind(&l35), TokenKind.kw_c_char, @intCast(u32, 35));
}

fn testDotVariants() void {
    const s: []const u8 = ".";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 0));

    const s2: []const u8 = "..";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.dot_dot, @intCast(u32, 0));

    const s3: []const u8 = "...";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.dot_dot_dot, @intCast(u32, 0));

    const s4: []const u8 = ".{";
    var l4 = makeLexer(s4);
    assertEqTokenKind(nextKind(&l4), TokenKind.dot_lbrace, @intCast(u32, 0));

    const s5: []const u8 = ".*";
    var l5 = makeLexer(s5);
    assertEqTokenKind(nextKind(&l5), TokenKind.dot_star, @intCast(u32, 0));

    const s6: []const u8 = "....";
    var l6 = makeLexer(s6);
    assertEqTokenKind(nextKind(&l6), TokenKind.dot_dot_dot, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l6), TokenKind.dot, @intCast(u32, 0));
}

fn testMultiTokenRecovery() void {
    const s: []const u8 = "42 ` 99";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.err_token, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));

    const s2: []const u8 = "@";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.err_token, @intCast(u32, 0));
}

fn testUnrecognizedChars() void {
    const s: []const u8 = "`";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.err_token, @intCast(u32, 0));

    const s2: []const u8 = "@`";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.err_token, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l2), TokenKind.err_token, @intCast(u32, 0));

    const s3: []const u8 = "`@`";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.err_token, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l3), TokenKind.err_token, @intCast(u32, 0));
    assertEqTokenKind(nextKind(&l3), TokenKind.err_token, @intCast(u32, 0));
}

fn testSwitchMultiProng() void {
    const s: []const u8 = "switch (x) { .A, .B, .C => {}, else => unreachable }";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_switch, @intCast(u32, 1300));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1301));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1302));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1303));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1304));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1305));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1306));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1307));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1308));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1309));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1310));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1311));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1312));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1313));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1314));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1315));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1316));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_else, @intCast(u32, 1317));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1318));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_unreachable, @intCast(u32, 1319));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1320));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1321));
}

fn testSwitchCapture() void {
    const s: []const u8 = "switch (x) { .A => |v| v, else => unreachable }";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_switch, @intCast(u32, 1400));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1401));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1402));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1403));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1404));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1405));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1406));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1407));
    assertEqTokenKind(nextKind(&l), TokenKind.pipe, @intCast(u32, 1408));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1409));
    assertEqTokenKind(nextKind(&l), TokenKind.pipe, @intCast(u32, 1410));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1411));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1412));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_else, @intCast(u32, 1413));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1414));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_unreachable, @intCast(u32, 1415));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1416));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1417));
}

fn testTryExpr() void {
    const s: []const u8 = "try foo(bar, baz)";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_try, @intCast(u32, 1420));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1421));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1422));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1423));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1424));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1425));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1426));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1427));
}

fn testErrorLiteral() void {
    const s: []const u8 = "return error.InvalidQuote";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_return, @intCast(u32, 1430));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_error, @intCast(u32, 1431));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1432));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1433));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1434));
}

fn testNestedSwitch() void {
    const s: []const u8 = "switch (a) { .X => switch (b) { .Y => {}, else => {} }, else => {} }";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_switch, @intCast(u32, 1440));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1441));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1442));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1443));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1444));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1445));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1446));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1447));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_switch, @intCast(u32, 1448));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1449));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1450));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1451));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1452));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1453));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1454));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1455));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1456));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1457));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1458));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_else, @intCast(u32, 1459));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1460));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1461));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1462));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1463));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1464));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_else, @intCast(u32, 1465));
    assertEqTokenKind(nextKind(&l), TokenKind.fat_arrow, @intCast(u32, 1466));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1467));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1468));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1469));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1470));
}

fn testIfExpr() void {
    const s: []const u8 = "if (cond) a else b";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_if, @intCast(u32, 1480));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1481));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1482));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1483));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1484));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_else, @intCast(u32, 1485));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1486));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1487));
}

fn testBuiltinCast() void {
    const s: []const u8 = "@ptrCast([*]u8, ptr)";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.builtin_identifier, @intCast(u32, 1490));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1491));
    assertEqTokenKind(nextKind(&l), TokenKind.lbracket, @intCast(u32, 1492));
    assertEqTokenKind(nextKind(&l), TokenKind.star, @intCast(u32, 1493));
    assertEqTokenKind(nextKind(&l), TokenKind.rbracket, @intCast(u32, 1494));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1495));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1496));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1497));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1498));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1499));
}

fn testSliceSyntax() void {
    const s: []const u8 = "arr[0..len]";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1500));
    assertEqTokenKind(nextKind(&l), TokenKind.lbracket, @intCast(u32, 1501));
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 1502));
    assertEqTokenKind(nextKind(&l), TokenKind.dot_dot, @intCast(u32, 1503));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1504));
    assertEqTokenKind(nextKind(&l), TokenKind.rbracket, @intCast(u32, 1505));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1506));
}

fn testOptionalCapture() void {
    const s: []const u8 = "if (opt) |val| {}";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_if, @intCast(u32, 1510));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1511));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1512));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1513));
    assertEqTokenKind(nextKind(&l), TokenKind.pipe, @intCast(u32, 1514));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1515));
    assertEqTokenKind(nextKind(&l), TokenKind.pipe, @intCast(u32, 1516));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1517));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1518));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1519));
}

fn testDerefField() void {
    const s: []const u8 = "curr_expr.*";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1520));
    assertEqTokenKind(nextKind(&l), TokenKind.dot_star, @intCast(u32, 1521));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1522));
}

fn testIntegrationMandelbrot() void {
    const s: []const u8 = "const s: f64 = 3.5; var x = 2.0; var y = 1.0e-5;";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_const, @intCast(u32, 1600));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1601));
    assertEqTokenKind(nextKind(&l), TokenKind.colon, @intCast(u32, 1602));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1603));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1604));
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 1605));
    assertEqTokenKind(nextKind(&l), TokenKind.semicolon, @intCast(u32, 1606));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_var, @intCast(u32, 1607));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1608));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1609));
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 1610));
    assertEqTokenKind(nextKind(&l), TokenKind.semicolon, @intCast(u32, 1611));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_var, @intCast(u32, 1612));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1613));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1614));
    assertEqTokenKind(nextKind(&l), TokenKind.float_literal, @intCast(u32, 1615));
    assertEqTokenKind(nextKind(&l), TokenKind.semicolon, @intCast(u32, 1616));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1617));
}

fn testIntegrationGameOfLife() void {
    const s: []const u8 = "const Cell = union(enum) { Dead, Alive }; var c: Cell = .{ .Alive = {} };";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_const, @intCast(u32, 1620));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1621));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1622));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_union, @intCast(u32, 1623));
    assertEqTokenKind(nextKind(&l), TokenKind.lparen, @intCast(u32, 1624));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_enum, @intCast(u32, 1625));
    assertEqTokenKind(nextKind(&l), TokenKind.rparen, @intCast(u32, 1626));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1627));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1628));
    assertEqTokenKind(nextKind(&l), TokenKind.comma, @intCast(u32, 1629));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1630));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1631));
    assertEqTokenKind(nextKind(&l), TokenKind.semicolon, @intCast(u32, 1632));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_var, @intCast(u32, 1633));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1634));
    assertEqTokenKind(nextKind(&l), TokenKind.colon, @intCast(u32, 1635));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1636));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1637));
    assertEqTokenKind(nextKind(&l), TokenKind.dot_lbrace, @intCast(u32, 1638));
    assertEqTokenKind(nextKind(&l), TokenKind.dot, @intCast(u32, 1639));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1640));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1641));
    assertEqTokenKind(nextKind(&l), TokenKind.lbrace, @intCast(u32, 1642));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1643));
    assertEqTokenKind(nextKind(&l), TokenKind.rbrace, @intCast(u32, 1644));
    assertEqTokenKind(nextKind(&l), TokenKind.semicolon, @intCast(u32, 1645));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1646));
}

fn testIntegrationMud() void {
    const s: []const u8 = "const msg: []const u8 = \"Welcome\\r\\n\";";
    var l = makeLexer(s);
    assertEqTokenKind(nextKind(&l), TokenKind.kw_const, @intCast(u32, 1650));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1651));
    assertEqTokenKind(nextKind(&l), TokenKind.colon, @intCast(u32, 1652));
    assertEqTokenKind(nextKind(&l), TokenKind.lbracket, @intCast(u32, 1653));
    assertEqTokenKind(nextKind(&l), TokenKind.rbracket, @intCast(u32, 1654));
    assertEqTokenKind(nextKind(&l), TokenKind.kw_const, @intCast(u32, 1655));
    assertEqTokenKind(nextKind(&l), TokenKind.identifier, @intCast(u32, 1656));
    assertEqTokenKind(nextKind(&l), TokenKind.eq, @intCast(u32, 1657));
    assertEqTokenKind(nextKind(&l), TokenKind.string_literal, @intCast(u32, 1658));
    assertEqTokenKind(nextKind(&l), TokenKind.semicolon, @intCast(u32, 1659));
    assertEqTokenKind(nextKind(&l), TokenKind.eof, @intCast(u32, 1660));
}
