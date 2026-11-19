// data_test.zig — native Linux tests for the M6 data.z98 scanner primitives
// (spec §25.10).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/data_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/data_test"
//   "$OUT/data_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const data = @import("../data.zig");

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

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parseIs(s: []const u8, want: i32) bool {
    if (data.parseI32(s)) |v| return v == want;
    return false;
}

fn parseNull(s: []const u8) bool {
    return data.parseI32(s) == null;
}

fn tParseI32() bool {
    if (!parseIs("0", 0)) return false;
    if (!parseIs("42", 42)) return false;
    if (!parseIs("-42", -42)) return false;
    if (!parseIs("2147483647", 2147483647)) return false;
    if (!parseIs("-2147483648", -2147483647 - 1)) return false;

    if (!parseNull("")) return false;
    if (!parseNull("12x")) return false;
    if (!parseNull(" 1")) return false;
    if (!parseNull("1 ")) return false;
    if (!parseNull("+1")) return false;
    if (!parseNull("-")) return false;
    if (!parseNull("2147483648")) return false;
    if (!parseNull("-2147483649")) return false;
    return true;
}

fn tClassifyBlankComment() bool {
    if (data.classifyLine("") != 0) return false;
    if (data.classifyLine("   ") != 0) return false;
    if (data.classifyLine("\r") != 0) return false;
    if (data.classifyLine("# comment") != 0) return false;
    if (data.classifyLine("   # indented") != 0) return false;
    return true;
}

fn tClassifyHeader() bool {
    if (data.classifyLine("format=2") != 1) return false;
    if (data.classifyLine(" format=2 ") != 1) return false;
    if (data.classifyLine("format=1") != 4) return false;
    if (data.classifyLine("format=3") != 4) return false;
    if (data.classifyLine("format=20") != 4) return false;
    if (data.classifyLine("format=2,x=1") != 4) return false;
    if (data.classifyLine("seed=98") != 3) return false;
    return true;
}

fn tClassifySection() bool {
    if (data.classifyLine("[creatures]") != 2) return false;
    if (data.classifyLine(" [tools] ") != 2) return false;
    if (data.classifyLine("[bogus]") != 2) return false;
    if (data.classifyLine("[creatures") != 4) return false;
    if (data.classifyLine("[]") != 4) return false;
    if (data.classifyLine("[a]b]") != 4) return false;
    return true;
}

fn tSectionIds() bool {
    if (data.sectionId("creatures") != 0) return false;
    if (data.sectionId("rules") != 1) return false;
    if (data.sectionId("tools") != 2) return false;
    if (data.sectionId("upgrades") != 3) return false;
    if (data.sectionId("cosmetics") != 4) return false;
    if (data.sectionId("encounter") != 5) return false;
    if (data.sectionId("zones") != 6) return false;
    if (data.sectionId("text") != 7) return false;
    if (data.sectionId("") != -1) return false;
    if (data.sectionId("Creatures") != -1) return false;
    if (data.sectionId("bogus") != -1) return false;
    if (data.sectionId("[creatures]") != -1) return false;
    return true;
}

fn tClassifyRow() bool {
    if (data.classifyLine("id=1") != 3) return false;
    if (data.classifyLine("  k = v  ") != 3) return false;
    if (data.classifyLine("a=b\r") != 3) return false;
    if (data.classifyLine("nope") != 4) return false;
    return true;
}

fn tRowBasic() bool {
    var out: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 0;
    if (!data.parseRowKV("id=1, name=Mystic Eel ,hp=5", &out, &n)) return false;
    if (n != 3) return false;
    if (!eql(out[0].key, "id")) return false;
    if (!eql(out[0].val, "1")) return false;
    if (!eql(out[1].key, "name")) return false;
    if (!eql(out[1].val, "Mystic Eel")) return false;
    if (!eql(out[2].key, "hp")) return false;
    if (!eql(out[2].val, "5")) return false;

    if (!data.parseRowKV("a = x y z", &out, &n)) return false;
    if (n != 1) return false;
    if (!eql(out[0].key, "a")) return false;
    if (!eql(out[0].val, "x y z")) return false;
    return true;
}

fn tRowCrlf() bool {
    if (data.classifyLine("a=1,b=2\r") != 3) return false;

    var out: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 0;
    if (!data.parseRowKV("a=1,b=2\r", &out, &n)) return false;
    if (n != 2) return false;
    if (!eql(out[1].key, "b")) return false;
    if (!eql(out[1].val, "2")) return false;
    return true;
}

fn rowRejects(s: []const u8) bool {
    var out: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 777;
    if (data.parseRowKV(s, &out, &n)) return false;
    return n == 777;
}

fn tRowMalformed() bool {
    if (!rowRejects("")) return false;
    if (!rowRejects("   ")) return false;
    if (!rowRejects("a")) return false;
    if (!rowRejects("a=1,")) return false;
    if (!rowRejects(",a=1")) return false;
    if (!rowRejects("=1")) return false;
    if (!rowRejects("a=")) return false;
    if (!rowRejects("a=1,,b=2")) return false;
    if (!rowRejects("a=1,b")) return false;
    return true;
}

fn tRowDuplicate() bool {
    if (!rowRejects("a=1,a=2")) return false;
    if (!rowRejects(" a=1 , a=2 ")) return false;
    return true;
}

fn buildFields(buf: []u8, count: usize) usize {
    var p: usize = 0;
    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        buf[p] = 'k';
        p += 1;
        buf[p] = @intCast(u8, 48 + idx / 10);
        p += 1;
        buf[p] = @intCast(u8, 48 + idx % 10);
        p += 1;
        buf[p] = '=';
        p += 1;
        buf[p] = 'v';
        p += 1;
        if (idx + 1 < count) {
            buf[p] = ',';
            p += 1;
        }
    }
    return p;
}

fn tRowCapacity() bool {
    var buf: [800]u8 = undefined;
    var out: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 0;

    const len_max = buildFields(buf[0..], data.ROW_MAX);
    if (!data.parseRowKV(buf[0..len_max], &out, &n)) return false;
    if (n != data.ROW_MAX) return false;

    const len_over = buildFields(buf[0..], data.ROW_MAX + 1);
    n = 555;
    if (data.parseRowKV(buf[0..len_over], &out, &n)) return false;
    return n == 555;
}

fn tRowFailurePreserves() bool {
    var out: [data.ROW_MAX]data.RowField = undefined;
    out[0] = data.RowField{ .key = "keep", .val = "me" };
    var n: usize = 9;
    if (data.parseRowKV("a=1,a=2", &out, &n)) return false;
    if (n != 9) return false;
    if (!eql(out[0].key, "keep")) return false;
    if (!eql(out[0].val, "me")) return false;
    return true;
}

fn fillPseudoRow(buf: []u8) void {
    buf[0] = 'a';
    buf[1] = '=';
    var i: usize = 2;
    while (i < buf.len) : (i += 1) {
        buf[i] = 'b';
    }
}

fn tLineCap() bool {
    var out: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 0;

    var ok: [data.MAX_LINE]u8 = undefined;
    fillPseudoRow(ok[0..]);
    if (data.classifyLine(ok[0..]) != 3) return false;
    if (!data.parseRowKV(ok[0..], &out, &n)) return false;
    if (n != 1) return false;

    var big: [data.MAX_LINE + 1]u8 = undefined;
    fillPseudoRow(big[0..]);
    if (data.classifyLine(big[0..]) != 4) return false;
    n = 42;
    if (data.parseRowKV(big[0..], &out, &n)) return false;
    return n == 42;
}

// The scanner has no section context, so it cannot reject a key that is
// unknown to a particular section. That schema check belongs to the loader /
// validator; here the raw row parses successfully.
fn tRowUnknownKeyDeferred() bool {
    var out: [data.ROW_MAX]data.RowField = undefined;
    var n: usize = 0;
    if (!data.parseRowKV("mystery=1", &out, &n)) return false;
    if (n != 1) return false;
    if (!eql(out[0].key, "mystery")) return false;
    if (!eql(out[0].val, "1")) return false;
    return true;
}

pub fn main() void {
    report("parse_i32_edges", tParseI32());
    report("classify_blank_comment", tClassifyBlankComment());
    report("classify_header", tClassifyHeader());
    report("classify_section", tClassifySection());
    report("section_ids", tSectionIds());
    report("classify_row", tClassifyRow());
    report("row_kv_basic", tRowBasic());
    report("row_kv_crlf", tRowCrlf());
    report("row_kv_rejects_malformed", tRowMalformed());
    report("row_kv_rejects_duplicate", tRowDuplicate());
    report("row_kv_capacity", tRowCapacity());
    report("row_kv_failure_preserves_n", tRowFailurePreserves());
    report("line_cap_4096", tLineCap());
    report("row_unknown_key_deferred", tRowUnknownKeyDeferred());

    if (fails != 0) os.exit(1);
    io.write("data_test PASS\n");
}
