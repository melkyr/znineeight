const pal = @import("../pal.zig");
const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
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
        var fmt_buf: [12]u8 = undefined;
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
    assertEqTokenKind(nextKind(&l), TokenKind.integer_literal, @intCast(u32, 0));

    const s2: []const u8 = "0xFFFF_FFFF";
    var l2 = makeLexer(s2);
    assertEqTokenKind(nextKind(&l2), TokenKind.integer_literal, @intCast(u32, 0));

    const s3: []const u8 = "0b1010_0101";
    var l3 = makeLexer(s3);
    assertEqTokenKind(nextKind(&l3), TokenKind.integer_literal, @intCast(u32, 0));

    const s4: []const u8 = "0o77_00";
    var l4 = makeLexer(s4);
    assertEqTokenKind(nextKind(&l4), TokenKind.integer_literal, @intCast(u32, 0));

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
