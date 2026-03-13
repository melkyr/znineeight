const file = @import("file.zig");
const arena_mod = @import("arena.zig");

pub const JsonValueTag = enum {
    Null,
    Boolean,
    Number,
    String,
    Array,
    Object,
};

pub const JsonObjectEntry = struct {
    key: []const u8,
    value: *JsonValue,
};

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: union {
        boolean: bool,
        number: f64,
        string: []const u8,
        array: []JsonValue,
        object: []JsonObjectEntry,
    },
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
    if (self.pos < self.input.len) {
        return self.input[self.pos];
    } else {
        return @intCast(u8, 0);
    }
}

fn parser_advance(self: *Parser) void {
    if (self.pos < self.input.len) {
        self.pos += 1;
    }
}

fn parser_skipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) {
        const c = self.input[self.pos];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            self.pos += 1;
        } else {
            break;
        }
    }
}

fn parser_expect(self: *Parser, c: u8) ParseError!void {
    if (parser_peek(self) != c) return error.ExpectedValue;
    parser_advance(self);
}

pub fn parseJson(arena_ptr: *void, input: []const u8) ParseError!JsonValue {
    const zero: usize = 0;
    var p = Parser{
        .input = input,
        .pos = zero,
        .arena = arena_ptr,
    };
    const result = try parseValue(&p);
    parser_skipWhitespace(&p);
    if (p.pos < p.input.len) return error.InvalidSyntax;
    return result;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    parser_skipWhitespace(p);
    const ch = parser_peek(p);
    if (ch == 'n') return try parseNull(p);
    if (ch == 't' or ch == 'f') return try parseBoolean(p);
    if (ch == '"') return try parseString(p);
    if ((ch >= '0' and ch <= '9') or ch == '-') return try parseNumber(p);
    if (ch == '[') return try parseArray(p);
    if (ch == '{') return try parseObject(p);
    return error.ExpectedValue;
}

fn sliceEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) return false;
        i += 1;
    }
    return true;
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    const null_str: []const u8 = "null";
    if (p.input.len - start < 4 or !sliceEqual(p.input[start .. start + 4], null_str)) return error.InvalidSyntax;
    p.pos += 4;
    var val: JsonValue = undefined;
    val.tag = JsonValueTag.Null;
    return val;
}

fn parseBoolean(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    const true_str: []const u8 = "true";
    const false_str: []const u8 = "false";
    if (p.input.len - start >= 4 and sliceEqual(p.input[start .. start + 4], true_str)) {
        p.pos += 4;
        var val: JsonValue = undefined;
        val.tag = JsonValueTag.Boolean;
        val.data.boolean = true;
        return val;
    }
    if (p.input.len - start >= 5 and sliceEqual(p.input[start .. start + 5], false_str)) {
        p.pos += 5;
        var val: JsonValue = undefined;
        val.tag = JsonValueTag.Boolean;
        val.data.boolean = false;
        return val;
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == '"') break;
        if (p.input[p.pos] == '\\') {
            p.pos += 1;
        }
        p.pos += 1;
    }
    if (p.pos >= p.input.len) return error.UnexpectedEnd;
    const slice = p.input[start..p.pos];
    try parser_expect(p, '"');

    var val: JsonValue = undefined;
    val.tag = JsonValueTag.String;
    val.data.string = slice;
    return val;
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
    const val_f = parseFloat(slice);

    var val: JsonValue = undefined;
    val.tag = JsonValueTag.Number;
    val.data.number = val_f;
    return val;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseFloat(s: []const u8) f64 {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < s.len and i < 63) {
        buf[i] = s[i];
        i += 1;
    }
    buf[i] = 0;
    const buf_ptr = @ptrCast([*]const u8, &buf);
    const endptr_null: ?*[*]const u8 = null;
    return file.strtod(buf_ptr, endptr_null);
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

    const bytes = arena_mod.alloc_bytes(p.arena, count * 32);
    const arr = @ptrCast([*]JsonValue, bytes.ptr)[0..count];

    var idx: usize = 0;
    if (parser_peek(p) != ']') {
        while (idx < count) {
            arr[idx] = try parseValue(p);
            idx += 1;
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

    var val: JsonValue = undefined;
    val.tag = JsonValueTag.Array;
    val.data.array = arr;
    return val;
}

fn parseObject(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '{');
    parser_skipWhitespace(p);
    var count: usize = 0;
    const saved = p.pos;
    if (parser_peek(p) != '}') {
        while (true) {
            const keyVal = try parseString(p);
            _ = keyVal;
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

    const bytes = arena_mod.alloc_bytes(p.arena, count * 16);
    const fields = @ptrCast([*]JsonObjectEntry, bytes.ptr)[0..count];

    var idx: usize = 0;
    if (parser_peek(p) != '}') {
        while (idx < count) {
            const keyVal = try parseString(p);
            const key = keyVal.data.string;

            parser_skipWhitespace(p);
            try parser_expect(p, ':');
            const val = try parseValue(p);

            const val_ptr_bytes = arena_mod.alloc_bytes(p.arena, 32);
            const val_ptr = @ptrCast(*JsonValue, val_ptr_bytes.ptr);
            val_ptr.tag = val.tag;
            val_ptr.data = val.data;

            fields[idx].key = key;
            fields[idx].value = val_ptr;
            idx += 1;
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

    var val: JsonValue = undefined;
    val.tag = JsonValueTag.Object;
    val.data.object = fields;
    return val;
}
