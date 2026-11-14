// lexer_test.zig — native Linux tests for the z9edit per-line lexer.
//
// Also prints a deterministic token dump (used by tier_edit.sh's 3x md5 gate).
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT/lexer" examples/z98/z9edit/tests/lexer_test.zig
//   sh "$OUT/lexer/build_target.sh" linux "$OUT/lexer/lexer_test"
//   "$OUT/lexer/lexer_test"

const io = @import("std_io");
const os = @import("std_os");
const lexer = @import("../lexer.zig");

const MAX_TOKENS: usize = 128;
var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn tokText(line: []const u8, t: lexer.Token) []const u8 {
    const s = @intCast(usize, t.start);
    const l = @intCast(usize, t.len);
    return line[s..s + l];
}

fn hasKind(line: []const u8, toks: []lexer.Token, n: usize, kind: lexer.TokKind, text: []const u8) bool {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (toks[i].kind == kind and eq(tokText(line, toks[i]), text)) return true;
    }
    return false;
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn tKeywordStringCommentNumber() bool {
    var st = lexer.lexInitState();
    var toks: [MAX_TOKENS]lexer.Token = undefined;
    var line: []const u8 = "var n = 42; \"s\" // c";
    const n = lexer.lexLine(&st, line, toks[0..]);
    return hasKind(line, toks[0..], n, .keyword, "var") and
        hasKind(line, toks[0..], n, .ident, "n") and
        hasKind(line, toks[0..], n, .number, "42") and
        hasKind(line, toks[0..], n, .string, "\"s\"") and
        hasKind(line, toks[0..], n, .comment, "// c");
}

fn tBlockCommentCarry() bool {
    var st = lexer.lexInitState();
    var toks: [MAX_TOKENS]lexer.Token = undefined;
    var l1: []const u8 = "a /* open";
    const n1 = lexer.lexLine(&st, l1, toks[0..]);
    if (!hasKind(l1, toks[0..], n1, .comment, "/* open")) return false;
    if (st.block_depth == 0) return false;
    var l2: []const u8 = "still */ b";
    const n2 = lexer.lexLine(&st, l2, toks[0..]);
    if (st.block_depth != 0) return false;
    return hasKind(l2, toks[0..], n2, .comment, "still */") and
        hasKind(l2, toks[0..], n2, .ident, "b");
}

fn tMultilineStringCarry() bool {
    var st = lexer.lexInitState();
    var toks: [MAX_TOKENS]lexer.Token = undefined;
    var l1: []const u8 = "var s = \"hello";
    const n1 = lexer.lexLine(&st, l1, toks[0..]);
    if (!hasKind(l1, toks[0..], n1, .string, "\"hello")) return false;
    if (!st.in_string) return false;
    var l2: []const u8 = "world\" + x";
    const n2 = lexer.lexLine(&st, l2, toks[0..]);
    if (st.in_string) return false;
    return hasKind(l2, toks[0..], n2, .string, "world\"") and
        hasKind(l2, toks[0..], n2, .ident, "x");
}

fn tBuiltinAndType() bool {
    var st = lexer.lexInitState();
    var toks: [MAX_TOKENS]lexer.Token = undefined;
    var line: []const u8 = "fn f(x: u32) @intCast(x)";
    const n = lexer.lexLine(&st, line, toks[0..]);
    return hasKind(line, toks[0..], n, .keyword, "fn") and
        hasKind(line, toks[0..], n, .type_name, "u32") and
        hasKind(line, toks[0..], n, .builtin, "@intCast");
}

fn tErrCodeToken() bool {
    var st = lexer.lexInitState();
    var toks: [MAX_TOKENS]lexer.Token = undefined;
    var line: []const u8 = "return error[3001];";
    const n = lexer.lexLine(&st, line, toks[0..]);
    return hasKind(line, toks[0..], n, .errcode, "error[3001]");
}

fn tErrCodeAtCol() bool {
    var line: []const u8 = "error[3048]";
    if (lexer.lexErrCodeAt(line, 0) != 3048) return false;
    if (lexer.lexErrCodeAt(line, 5) != 3048) return false;
    if (lexer.lexErrCodeAt(line, 6) != 3048) return false;
    if (lexer.lexErrCodeAt(line, 10) != 3048) return false;
    if (lexer.lexErrCodeAt(line, 11) != 0) return false;
    var other: []const u8 = "const x = 1;";
    if (lexer.lexErrCodeAt(other, 0) != 0) return false;
    return true;
}

fn kindName(k: lexer.TokKind) []const u8 {
    if (k == .plain) return "plain";
    if (k == .keyword) return "keyword";
    if (k == .builtin) return "builtin";
    if (k == .errcode) return "errcode";
    if (k == .string) return "string";
    if (k == .comment) return "comment";
    if (k == .number) return "number";
    if (k == .type_name) return "type_name";
    if (k == .ident) return "ident";
    return "punct";
}

fn dumpLine(tag: []const u8, st: *lexer.LexState, line: []const u8) void {
    var toks: [MAX_TOKENS]lexer.Token = undefined;
    const n = lexer.lexLine(st, line, toks[0..]);
    io.write("dump ");
    io.write(tag);
    io.write(" n=");
    io.printInt(@intCast(i32, n));
    var i: usize = 0;
    while (i < n) : (i += 1) {
        io.write(" ");
        io.write(kindName(toks[i].kind));
        io.write(":");
        io.printInt(@intCast(i32, toks[i].start));
        io.write("+");
        io.printInt(@intCast(i32, toks[i].len));
    }
    io.write("\n");
}

pub fn main() void {
    report("keyword_string_comment_number", tKeywordStringCommentNumber());
    report("block_comment_state_carry", tBlockCommentCarry());
    report("multiline_string_state_carry", tMultilineStringCarry());
    report("builtin_and_type", tBuiltinAndType());
    report("errcode_token", tErrCodeToken());
    report("errcode_at_col", tErrCodeAtCol());

    var ds = lexer.lexInitState();
    var d1: []const u8 = "const x = 42 // c";
    dumpLine("a", &ds, d1);
    var d2: []const u8 = "/* open";
    dumpLine("b", &ds, d2);
    var d3: []const u8 = "close */ @import";
    dumpLine("c", &ds, d3);
    var d4: []const u8 = "\"carry";
    dumpLine("d", &ds, d4);
    var d5: []const u8 = "on\" error[3000]";
    dumpLine("e", &ds, d5);

    if (fails != 0) os.exit(1);
}
