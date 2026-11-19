// data.zig — UNDERSANDED M6 data.z98 scanner primitives (spec §25.10).
//
// Task 2 is pure scanner work: no file I/O, no arena, no Tables. Task 3 owns
// whole-file reading and loadFile(arena, path, tables); it consumes the
// primitives below. Row schema/unknown-key checks belong to Task 3/4 because
// this scanner has no section context.

const parse = @import("std_parse");

// §25.10 row-line cap (bytes, \r excluded).
pub const MAX_LINE: usize = 4096;

// Broadest authored row is [creatures] at 61 keys; 80 leaves headroom.
pub const ROW_MAX: usize = 80;

pub const RowField = struct { key: []const u8, val: []const u8 };

pub fn parseI32(s: []const u8) ?i32 {
    return parse.parseInt(s);
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn stripCR(line: []const u8) []const u8 {
    if (line.len > 0 and line[line.len - 1] == '\r') {
        return line[0 .. line.len - 1];
    }
    return line;
}

fn trimSpaces(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] == ' ') : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

pub fn sectionId(name: []const u8) i32 {
    if (eql(name, "creatures")) return 0;
    if (eql(name, "rules")) return 1;
    if (eql(name, "tools")) return 2;
    if (eql(name, "upgrades")) return 3;
    if (eql(name, "cosmetics")) return 4;
    if (eql(name, "encounter")) return 5;
    if (eql(name, "zones")) return 6;
    if (eql(name, "text")) return 7;
    return -1;
}

// 0 blank/comment, 1 header, 2 section, 3 row, 4 error. Stateless: unknown
// section names and unknown row keys are later loader/validator concerns.
pub fn classifyLine(line: []const u8) i32 {
    const s = stripCR(line);
    if (s.len > MAX_LINE) return 4;

    const t = trimSpaces(s);
    if (t.len == 0) return 0;
    if (t[0] == '#') return 0;

    if (eql(t, "format=2")) return 1;
    if (t.len >= 7 and eql(t[0..7], "format=")) return 4;

    if (t[0] == '[') {
        var i: usize = 1;
        while (i < t.len) : (i += 1) {
            if (t[i] == ']') {
                if (i == t.len - 1 and i > 1) return 2;
                return 4;
            }
        }
        return 4;
    }

    var i: usize = 0;
    while (i < t.len) : (i += 1) {
        if (t[i] == '=') return 3;
    }
    return 4;
}

// Comma-separated key=value fields, surrounding spaces trimmed, inner spaces
// kept. Rejects missing '=', empty key/value, duplicate key, and > ROW_MAX
// fields. All-or-nothing: out and n are written only on success.
pub fn parseRowKV(line: []const u8, out: *[ROW_MAX]RowField, n: *usize) bool {
    const s = stripCR(line);
    if (s.len > MAX_LINE) return false;

    var tmp: [ROW_MAX]RowField = undefined;
    var count: usize = 0;
    var start: usize = 0;
    var i: usize = 0;

    while (i <= s.len) : (i += 1) {
        if (i != s.len and s[i] != ',') continue;

        const field = trimSpaces(s[start..i]);
        var eq: usize = 0;
        var found: bool = false;
        while (eq < field.len and !found) : (eq += 1) {
            if (field[eq] == '=') found = true;
        }
        if (!found) return false;

        const key = trimSpaces(field[0..eq - 1]);
        const val = trimSpaces(field[eq..]);
        if (key.len == 0 or val.len == 0) return false;

        var k: usize = 0;
        while (k < count) : (k += 1) {
            if (eql(tmp[k].key, key)) return false;
        }

        if (count >= ROW_MAX) return false;
        tmp[count] = RowField{ .key = key, .val = val };
        count += 1;
        start = i + 1;
    }

    var j: usize = 0;
    while (j < count) : (j += 1) {
        out[j] = tmp[j];
    }
    n.* = count;
    return true;
}
