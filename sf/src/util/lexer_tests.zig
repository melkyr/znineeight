const test_utils = @import("test_utils.zig");
const LexerTestHarness = test_utils.LexerTestHarness;
const lexerTestHarnessInit = test_utils.lexerTestHarnessInit;
const lexerTestHarnessNextKind = test_utils.lexerTestHarnessNextKind;
const alloc_mod = @import("../allocator.zig");
const token_mod = @import("../token.zig");
const TokenKind = token_mod.TokenKind;
const interner_mod = @import("../string_interner.zig");
const diag_mod = @import("../diagnostics.zig");
const Diagnostic = diag_mod.Diagnostic;
const assert_true = @import("../test_runner.zig").assert_true;
const assert_eq_u32 = @import("../test_runner.zig").assert_eq_u32;
const assert_eq_u64 = @import("../test_runner.zig").assert_eq_u64;
const assert_eq_str = @import("../test_runner.zig").assert_eq_str;

fn assert_eq_u8(actual: u8, expected: u8, msg: []const u8) void {
    if (actual != expected) {
        var bp: usize = 0;
        while (bp == 0) {}
    }
}

fn assert_eq_bool(actual: bool, expected: bool, msg: []const u8) void {
    if (actual != expected) {
        var bp: usize = 0;
        while (bp == 0) {}
    }
}

// --- Task 36: Lexer struct fields ---
fn test_lexer_fields() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "abc", 42);
    assert_eq_u32(h.lexer.pos, 0, "init pos");
    assert_eq_u32(h.lexer.line, 1, "init line");
    assert_eq_u32(h.lexer.col, 1, "init col");
    assert_eq_u32(h.lexer.file_id, 42, "init file_id");
}

// --- Task 37: Helper methods ---
fn test_lexer_advance() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "abc", 0);
    assert_eq_u8(h.lexer.advance(), 'a', "advance first");
    assert_eq_u32(h.lexer.pos, 1, "pos after first");
    assert_eq_u8(h.lexer.advance(), 'b', "advance second");
    assert_eq_u32(h.lexer.pos, 2, "pos after second");
}

fn test_lexer_advance_eof() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "", 0);
    assert_eq_u8(h.lexer.advance(), 0, "advance empty returns 0");
    assert_eq_u32(h.lexer.pos, 0, "advance empty does not advance");
}

fn test_lexer_advance_line_col() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "ab\ncd", 0);
    assert_eq_u8(h.lexer.advance(), 'a', "advance a");
    assert_eq_u32(h.lexer.line, 1, "line after a");
    assert_eq_u32(h.lexer.col, 2, "col after a");
    _ = h.lexer.advance(); // 'b'
    _ = h.lexer.advance(); // '\n'
    assert_eq_u32(h.lexer.line, 2, "line after newline");
    assert_eq_u32(h.lexer.col, 1, "col after newline");
    _ = h.lexer.advance(); // 'c'
    assert_eq_u32(h.lexer.col, 2, "col after c");
}

fn test_lexer_peek() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "abc", 0);
    assert_eq_u8(h.lexer.peek(), 'a', "peek first");
    assert_eq_u32(h.lexer.pos, 0, "peek did not advance");
    _ = h.lexer.advance();
    assert_eq_u8(h.lexer.peek(), 'b', "peek second");
}

fn test_lexer_peek_eof() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "", 0);
    assert_eq_u8(h.lexer.peek(), 0, "peek empty returns 0");
}

fn test_lexer_peekN() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "abcde", 0);
    assert_eq_u8(h.lexer.peekN(0), 'a', "peekN 0");
    assert_eq_u8(h.lexer.peekN(1), 'b', "peekN 1");
    assert_eq_u8(h.lexer.peekN(2), 'c', "peekN 2");
    assert_eq_u32(h.lexer.pos, 0, "peekN did not advance");
}

fn test_lexer_peekN_eof() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "ab", 0);
    assert_eq_u8(h.lexer.peekN(2), 0, "peekN past eof returns 0");
    assert_eq_u8(h.lexer.peekN(99), 0, "peekN far past eof returns 0");
}

fn test_lexer_isAtEnd() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "", 0);
    assert_eq_bool(h.lexer.isAtEnd(), true, "isAtEnd empty");
}

fn test_lexer_isAtEnd_not() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "xyz", 0);
    assert_eq_bool(h.lexer.isAtEnd(), false, "isAtEnd non-empty");
    _ = h.lexer.advance();
    assert_eq_bool(h.lexer.isAtEnd(), false, "isAtEnd after one");
    _ = h.lexer.advance();
    _ = h.lexer.advance();
    assert_eq_bool(h.lexer.isAtEnd(), true, "isAtEnd consumed all");
}

fn test_lexer_match() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "ab", 0);
    assert_eq_bool(h.lexer.match('a'), true, "match true");
    assert_eq_u32(h.lexer.pos, 1, "match true advanced");
    assert_eq_bool(h.lexer.match('c'), false, "match false");
    assert_eq_u32(h.lexer.pos, 1, "match false did not advance");
    assert_eq_bool(h.lexer.match('b'), true, "match second");
}

fn test_lexer_match_eof() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "", 0);
    assert_eq_bool(h.lexer.match('x'), false, "match at eof false");
}

// --- Task 38: skipWhitespaceAndComments ---
fn test_lexer_skip_whitespace() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "   \t\n  x", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .identifier, "skip ws yields identifier");
}

fn test_lexer_line_comment() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "// comment\n42", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .integer_literal, "line comment skipped");
}

fn test_lexer_block_comment() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "/* block */42", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .integer_literal, "block comment skipped");
}

fn test_lexer_nested_block_comment() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "/* outer /* inner */ more */x", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .identifier, "nested block comment");
}

fn test_lexer_unterminated_block_comment() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "/* no end ", 0);
    var tok = h.lexer.nextToken();
    _ = tok;
    assert_true(h.diag.diagnostics.len > 0, "unterminated comment diag emitted");
}

// --- Tasks 40-45: Dot variants, operators, delimiters ---
fn test_lexer_dot_variants() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, ". .. ... .{ .*", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .dot, "dot");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .dot_dot, "dot_dot");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .dot_dot_dot, "dot_dot_dot");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .dot_lbrace, "dot_lbrace");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .dot_star, "dot_star");
}

fn test_lexer_operators() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "+ - * / % & | ^ ~ << >>", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .plus, "plus");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .minus, "minus");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .star, "star");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .slash, "slash");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .percent, "percent");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .ampersand, "ampersand");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .pipe, "pipe");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .caret, "caret");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .tilde, "tilde");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .shl, "shl");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .shr, "shr");
}

fn test_lexer_comparison() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "< > <= >= == !=", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .less, "less");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .greater, "greater");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .less_eq, "less_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .greater_eq, "greater_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .eq_eq, "eq_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .bang_eq, "bang_eq");
}

fn test_lexer_assignment() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "= += -= *= /= %= &= |= ^= <<= >>=", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .eq, "eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .plus_eq, "plus_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .minus_eq, "minus_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .star_eq, "star_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .slash_eq, "slash_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .percent_eq, "percent_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .ampersand_eq, "ampersand_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .pipe_eq, "pipe_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .caret_eq, "caret_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .shl_eq, "shl_eq");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .shr_eq, "shr_eq");
}

fn test_lexer_delimiters() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "( ) [ ] { } ; : ,", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .lparen, "lparen");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .rparen, "rparen");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .lbracket, "lbracket");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .rbracket, "rbracket");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .lbrace, "lbrace");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .rbrace, "rbrace");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .semicolon, "semicolon");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .colon, "colon");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .comma, "comma");
}

fn test_lexer_special() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "_ ? ! =>", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .underscore, "underscore");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .question_mark, "question_mark");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .bang, "bang");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .fat_arrow, "fat_arrow");
}

fn test_lexer_bare_at() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "@", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .err_token, "bare @ returns err_token");
    assert_true(h.diag.diagnostics.len > 0, "bare @ diag emitted");
}

// --- Task 46: scanNumber ---
fn test_lexer_integer_decimal() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "42", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .integer_literal, "integer decimal kind");
    assert_eq_u64(tok.value.int_val, 42, "integer decimal value");
}

fn test_lexer_integer_hex() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "0xFF", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .integer_literal, "integer hex kind");
    assert_eq_u64(tok.value.int_val, 255, "integer hex value");
}

fn test_lexer_integer_binary() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "0b1010", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .integer_literal, "integer binary kind");
    assert_eq_u64(tok.value.int_val, 10, "integer binary value");
}

fn test_lexer_integer_octal() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "0o77", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .integer_literal, "integer octal kind");
    assert_eq_u64(tok.value.int_val, 63, "integer octal value");
}

fn test_lexer_float_basic() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "3.14", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .float_literal, "float basic kind");
}

fn test_lexer_float_range_disambig() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "0..10", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .integer_literal, "float disambig int");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .dot_dot, "float disambig dot_dot");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .integer_literal, "float disambig int 2");
}

// --- Task 48: scanString ---
fn test_lexer_string_basic() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "\"hello\"", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .string_literal, "string basic kind");
}

fn test_lexer_string_empty() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "\"\"", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .string_literal, "string empty");
}

fn test_lexer_string_unterminated() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "\"no end", 0);
    var tok = h.lexer.nextToken();
    _ = tok;
    assert_true(h.diag.diagnostics.len > 0, "unterminated string diag");
}

// --- Task 49: scanChar ---
fn test_lexer_char_basic() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "'a'", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .char_literal, "char basic kind");
    assert_eq_u64(tok.value.int_val, 'a', "char basic value");
}

fn test_lexer_char_escape() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "'\\n'", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .char_literal, "char escape kind");
    assert_eq_u64(tok.value.int_val, 10, "char escape value (newline=10)");
}

fn test_lexer_char_empty() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "''", 0);
    var tok = h.lexer.nextToken();
    _ = tok;
    assert_true(h.diag.diagnostics.len > 0, "empty char diag");
}

// --- Task 50: scanIdentifierOrKeyword ---
fn test_lexer_identifier() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "foo", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .identifier, "identifier kind");
    var text = interner_mod.stringInternerGet(&h.interner, tok.value.string_id);
    assert_eq_str(text, "foo", "identifier text");
}

fn test_lexer_underscore() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "_", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .underscore, "underscore bare");
}

fn test_lexer_underscore_ident() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "_foo", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .identifier, "underscore ident");
}

fn test_lexer_keyword() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "const fn if", 0);
    assert_eq_u8(lexerTestHarnessNextKind(&h), .kw_const, "keyword const");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .kw_fn, "keyword fn");
    assert_eq_u8(lexerTestHarnessNextKind(&h), .kw_if, "keyword if");
}

fn test_lexer_builtin() void {
    var h: LexerTestHarness = undefined;
    lexerTestHarnessInit(&h, "@sizeOf", 0);
    var tok = h.lexer.nextToken();
    assert_true(tok.kind == .builtin_identifier, "builtin kind");
    var text = interner_mod.stringInternerGet(&h.interner, tok.value.string_id);
    assert_eq_str(text, "@sizeOf", "builtin text includes @");
}

pub fn main() void {
    test_lexer_fields();
    test_lexer_advance();
    test_lexer_advance_eof();
    test_lexer_advance_line_col();
    test_lexer_peek();
    test_lexer_peek_eof();
    test_lexer_peekN();
    test_lexer_peekN_eof();
    test_lexer_isAtEnd();
    test_lexer_isAtEnd_not();
    test_lexer_match();
    test_lexer_match_eof();
    test_lexer_skip_whitespace();
    test_lexer_line_comment();
    test_lexer_block_comment();
    test_lexer_nested_block_comment();
    test_lexer_unterminated_block_comment();
    test_lexer_dot_variants();
    test_lexer_operators();
    test_lexer_comparison();
    test_lexer_assignment();
    test_lexer_delimiters();
    test_lexer_special();
    test_lexer_bare_at();
    test_lexer_integer_decimal();
    test_lexer_integer_hex();
    test_lexer_integer_binary();
    test_lexer_integer_octal();
    test_lexer_float_basic();
    test_lexer_float_range_disambig();
    test_lexer_string_basic();
    test_lexer_string_empty();
    test_lexer_string_unterminated();
    test_lexer_char_basic();
    test_lexer_char_escape();
    test_lexer_char_empty();
    test_lexer_identifier();
    test_lexer_underscore();
    test_lexer_underscore_ident();
    test_lexer_keyword();
    test_lexer_builtin();
}
