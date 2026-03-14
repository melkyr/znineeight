const file = @import("file.zig");
const arena = @import("arena.zig");

pub const JsonValue = union(enum) {
    Null,
    Boolean: bool,
    Number: f64,
    String: []const u8,
    Array: []JsonValue,
    Object: []struct { key: []const u8, value: JsonValue },
};

pub const ParseError = error{
    InvalidSyntax,
    UnexpectedEnd,
    ExpectedValue,
    ExpectedKey,
    ExpectedColon,
    ExpectedCommaOrEnd,
    OutOfMemory,
};

const Parser = struct {
    input: []const u8,
    pos: usize,
    arena: *void,
};

fn parser_peek(self: *Parser) u8 {
    return if (self.pos < self.input.len) self.input[self.pos] else 0;
}

fn parser_advance(self: *Parser) void {
    if (self.pos < self.input.len) self.pos += 1;
}

fn parser_skipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) : (self.pos += 1) {
        switch (self.input[self.pos]) {
            ' ', '\t', '\n', '\r' => continue;,
            else => break;,
        }
    }
}

fn parser_expect(self: *Parser, c: u8) ParseError!void {
    if (parser_peek(self) != c) return error.ExpectedValue;
    parser_advance(self);
}

pub fn parseJson(arena_ptr: *void, input: []const u8) ParseError!JsonValue {
    var p = Parser{ .input = input, .pos = 0, .arena = arena_ptr };
    const result = try parseValue(&p);
    parser_skipWhitespace(&p);
    if (p.pos < p.input.len) return error.InvalidSyntax;
    return result;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    parser_skipWhitespace(p);
    const ch = parser_peek(p);
    return switch (ch) {
        'n' => try parseNull(p),
        't', 'f' => try parseBoolean(p),
        '"' => try parseString(p),
        '0'...'9', '-' => try parseNumber(p),
        '[' => try parseArray(p),
        '{' => try parseObject(p),
        else => error.ExpectedValue,
    };
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos < 4 or !sliceEqual(p.input[p.pos..p.pos + 4], "null")) return error.InvalidSyntax;
    p.pos += 4;
    return JsonValue.Null;
}

fn sliceEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parseBoolean(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos >= 4 and sliceEqual(p.input[p.pos..p.pos + 4], "true")) {
        p.pos += 4;
        return JsonValue{ .Boolean = true };
    }
    if (p.input.len - p.pos >= 5 and sliceEqual(p.input[p.pos..p.pos + 5], "false")) {
        p.pos += 5;
        return JsonValue{ .Boolean = false };
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) : (p.pos += 1) {
        if (p.input[p.pos] == '"') break;
        if (p.input[p.pos] == '\\') p.pos += 1;
    }
    if (p.pos >= p.input.len) return error.UnexpectedEnd;
    const slice = p.input[start..p.pos];
    try parser_expect(p, '"');
    return JsonValue{ .String = slice };
}

fn parseNumber(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    if (parser_peek(p) == '-') parser_advance(p);
    while (isDigit(parser_peek(p))) parser_advance(p);
    if (parser_peek(p) == '.') {
        parser_advance(p);
        while (isDigit(parser_peek(p))) parser_advance(p);
    }
    if (parser_peek(p) == 'e' or parser_peek(p) == 'E') {
        parser_advance(p);
        if (parser_peek(p) == '+' or parser_peek(p) == '-') parser_advance(p);
        while (isDigit(parser_peek(p))) parser_advance(p);
    }
    const slice = p.input[start..p.pos];
    const val = parseFloat(slice);
    return JsonValue{ .Number = val };
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseFloat(s: []const u8) f64 {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < s.len and i < 63) : (i += 1) {
        buf[i] = s[i];
    }
    buf[i] = 0;
    return file.strtod(&buf, null);
}

fn parseArray(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '[');
    parser_skipWhitespace(p);
    var count: usize = 0;
    const saved = p.pos;
    if (parser_peek(p) != ']') {
        while (true) {
            _ = try parseValue(p);
            count += 1;
            parser_skipWhitespace(p);
            if (parser_peek(p) == ',') {
                parser_advance(p);
                parser_skipWhitespace(p);
                continue;
            }
            break;
        }
        if (parser_peek(p) != ']') return error.ExpectedCommaOrEnd;
    }
    p.pos = saved;
    const arr = arena.alloc(p.arena, JsonValue, count);
    var idx: usize = 0;
    if (parser_peek(p) != ']') {
        while (idx < count) : (idx += 1) {
            arr[idx] = try parseValue(p);
            parser_skipWhitespace(p);
            if (parser_peek(p) == ',') {
                parser_advance(p);
                parser_skipWhitespace(p);
                continue;
            }
            break;
        }
    }
    try parser_expect(p, ']');
    return JsonValue{ .Array = arr };
}

fn parseObject(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '{');
    parser_skipWhitespace(p);
    var count: usize = 0;
    const saved = p.pos;
    if (parser_peek(p) != '}') {
        while (true) {
            _ = try parseString(p);
            parser_skipWhitespace(p);
            try parser_expect(p, ':');
            _ = try parseValue(p);
            count += 1;
            parser_skipWhitespace(p);
            if (parser_peek(p) == ',') {
                parser_advance(p);
                parser_skipWhitespace(p);
                continue;
            }
            break;
        }
        if (parser_peek(p) != '}') return error.ExpectedCommaOrEnd;
    }
    p.pos = saved;
    const fields = arena.alloc(p.arena, struct { key: []const u8, value: JsonValue }, count);
    var idx: usize = 0;
    if (parser_peek(p) != '}') {
        while (idx < count) : (idx += 1) {
            const keyVal = try parseString(p);
            const key = switch (keyVal) { .String => |s| s, else => unreachable };
            parser_skipWhitespace(p);
            try parser_expect(p, ':');
            const val = try parseValue(p);
            fields[idx] = .{ .key = key, .value = val };
            parser_skipWhitespace(p);
            if (parser_peek(p) == ',') {
                parser_advance(p);
                parser_skipWhitespace(p);
                continue;
            }
            break;
        }
    }
    try parser_expect(p, '}');
    return JsonValue{ .Object = fields };
}
