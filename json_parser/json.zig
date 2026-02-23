// json.zig
const file = @import("file.zig");

pub const JsonValueTag = enum {
    Null,
    Boolean,
    Number,
    String,
    Array,
    Object,
};

pub const JsonObjectField = struct {
    key: []const u8,
    value: *JsonValue,
};

pub const JsonValueData = union {
    dummy: u8,
    boolean: bool,
    number: f64,
    string: []const u8,
    array: []JsonValue,
    object: []JsonObjectField,
};

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: JsonValueData,
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

fn peek(self: *Parser) u8 {
    return if (self.pos < self.input.len) self.input[self.pos] else 0;
}

fn advance(self: *Parser) void {
    if (self.pos < self.input.len) { self.pos += 1; }
}

fn skipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) {
        const ch = self.input[self.pos];
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
            self.pos += 1;
            continue;
        } else {
            break;
        }
    }
}

fn expect(self: *Parser, c: u8) ParseError!void {
    if (peek(self) != c) { return error.ExpectedValue; }
    advance(self);
}

extern fn arena_alloc(arena: *void, size: usize) *void;

pub fn parseJson(arena: *void, input: []const u8) ParseError!JsonValue {
    var p = Parser{ .input = input, .pos = 0, .arena = arena };
    const result = try parseValue(&p);
    skipWhitespace(&p);
    if (p.pos < p.input.len) { return error.InvalidSyntax; }
    return result;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    skipWhitespace(p);
    const ch = peek(p);
    if (ch == 'n') { return try parseNull(p); }
    if (ch == 't' or ch == 'f') { return try parseBoolean(p); }
    if (ch == '"') { return try parseString(p); }
    if (ch == '[') { return try parseArray(p); }
    if (ch == '{') { return try parseObject(p); }
    if ((ch >= '0' and ch <= '9') or ch == '-') { return try parseNumber(p); }

    return error.ExpectedValue;
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos < 4) { return error.InvalidSyntax; }
    if (p.input[p.pos] == 'n' and p.input[p.pos+1] == 'u' and p.input[p.pos+2] == 'l' and p.input[p.pos+3] == 'l') {
        p.pos += 4;
        var val: JsonValue = undefined;
        val.tag = JsonValueTag.Null;
        return val;
    }
    return error.InvalidSyntax;
}

fn parseBoolean(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos >= 4 and p.input[p.pos] == 't') {
        if (p.input[p.pos+1] == 'r' and p.input[p.pos+2] == 'u' and p.input[p.pos+3] == 'e') {
            p.pos += 4;
            var val: JsonValue = undefined;
            val.tag = JsonValueTag.Boolean;
            val.data.boolean = true;
            return val;
        }
    }
    if (p.input.len - p.pos >= 5 and p.input[p.pos] == 'f') {
        if (p.input[p.pos+1] == 'a' and p.input[p.pos+2] == 'l' and p.input[p.pos+3] == 's' and p.input[p.pos+4] == 'e') {
            p.pos += 5;
            var val: JsonValue = undefined;
            val.tag = JsonValueTag.Boolean;
            val.data.boolean = false;
            return val;
        }
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try expect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == '"') { break; }
        if (p.input[p.pos] == '\\') { p.pos += 1; }
        p.pos += 1;
    }
    if (p.pos >= p.input.len) { return error.UnexpectedEnd; }
    const slice = p.input[start..p.pos];
    try expect(p, '"');
    var val: JsonValue = undefined;
    val.tag = JsonValueTag.String;
    val.data.string = slice;
    return val;
}

fn parseNumber(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    if (peek(p) == '-') { advance(p); }
    while (isDigit(peek(p))) { advance(p); }
    if (peek(p) == '.') {
        advance(p);
        while (isDigit(peek(p))) { advance(p); }
    }
    if (peek(p) == 'e' or peek(p) == 'E') {
        advance(p);
        if (peek(p) == '+' or peek(p) == '-') { advance(p); }
        while (isDigit(peek(p))) { advance(p); }
    }
    const slice = p.input[start..p.pos];
    const val = try parseFloat(slice);
    var res: JsonValue = undefined;
    res.tag = JsonValueTag.Number;
    res.data.number = val;
    return res;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseFloat(s: []const u8) ParseError!f64 {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    while (i < s.len and i < 63) {
        buf[i] = s[i];
        i += 1;
    }
    buf[i] = 0;
    const result = file.strtod(@ptrCast([*]const u8, &buf[0]), null);
    return result;
}

fn parseArray(p: *Parser) ParseError!JsonValue {
    try expect(p, '[');
    skipWhitespace(p);

    var count: usize = 0;
    var saved_pos = p.pos;
    if (peek(p) != ']') {
        while (true) {
            _ = try parseValue(p);
            count += 1;
            skipWhitespace(p);
            if (peek(p) == ',') {
                advance(p);
                skipWhitespace(p);
                continue;
            }
            break;
        }
        if (peek(p) != ']') { return error.ExpectedCommaOrEnd; }
    }

    p.pos = saved_pos;
    skipWhitespace(p);

    const arr_ptr = @ptrCast([*]JsonValue, arena_alloc(p.arena, @sizeOf(JsonValue) * count));
    const arr = arr_ptr[0..count];
    var idx: usize = 0;
    if (peek(p) != ']') {
        while (true) {
            arr[idx] = try parseValue(p);
            idx += 1;
            skipWhitespace(p);
            if (peek(p) == ',') {
                advance(p);
                skipWhitespace(p);
                continue;
            }
            break;
        }
    }
    try expect(p, ']');
    var val: JsonValue = undefined;
    val.tag = JsonValueTag.Array;
    val.data.array = arr;
    return val;
}

fn parseObject(p: *Parser) ParseError!JsonValue {
    try expect(p, '{');
    skipWhitespace(p);

    var count: usize = 0;
    var saved_pos = p.pos;
    if (peek(p) != '}') {
        while (true) {
            const keyVal = try parseString(p);
            _ = keyVal;
            skipWhitespace(p);
            try expect(p, ':');
            _ = try parseValue(p);
            count += 1;
            skipWhitespace(p);
            if (peek(p) == ',') {
                advance(p);
                skipWhitespace(p);
                continue;
            }
            break;
        }
        if (peek(p) != '}') { return error.ExpectedCommaOrEnd; }
    }
    p.pos = saved_pos;
    skipWhitespace(p);

    const fields_ptr = @ptrCast([*]JsonObjectField, arena_alloc(p.arena, @sizeOf(JsonObjectField) * count));
    const fields = fields_ptr[0..count];
    var idx: usize = 0;
    if (peek(p) != '}') {
        while (true) {
            const keyVal = try parseString(p);
            const key = keyVal.data.string;
            skipWhitespace(p);
            try expect(p, ':');
            const val = try parseValue(p);
            const val_ptr = @ptrCast(*JsonValue, arena_alloc(p.arena, @sizeOf(JsonValue)));
            val_ptr.* = val;
            fields[idx].key = key;
            fields[idx].value = val_ptr;
            idx += 1;
            skipWhitespace(p);
            if (peek(p) == ',') {
                advance(p);
                skipWhitespace(p);
                continue;
            }
            break;
        }
    }
    try expect(p, '}');
    var res: JsonValue = undefined;
    res.tag = JsonValueTag.Object;
    res.data.object = fields;
    return res;
}
