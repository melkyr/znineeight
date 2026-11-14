const file = @import("file.zig");

pub const JsonProperty = struct { key: []const u8, value: *JsonValue };

pub const JsonValueTag = enum {
    Null,
    Boolean,
    Number,
    String,
    Array,
    Object,
};

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: JsonData,
};

pub const JsonData = union {
    Boolean: bool,
    Number: f64,
    String: []const u8,
    Array: []JsonValue,
    Object: []JsonProperty,
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

fn peek(p: *Parser) u8 {
    if (p.pos < p.input.len) {
        return p.input[p.pos];
    } else {
        const nul: u8 = 0;
        return nul;
    }
}

fn advance(p: *Parser) void {
    if (p.pos < p.input.len) p.pos += 1;
}

fn skipWhitespace(p: *Parser) void {
    while (p.pos < p.input.len) {
        const ch = p.input[p.pos];
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
            p.pos += 1;
        } else {
            break;
        }
    }
}

fn expect(p: *Parser, c: u8) ParseError!void {
    if (peek(p) != c) return error.ExpectedValue;
    advance(p);
}

pub fn parseJson(arena_ptr: *void, input: []const u8) ParseError!*JsonValue {
    const zero: usize = 0;
    var p = Parser{ .input = input, .pos = zero, .arena = arena_ptr };
    const result = try parseValue(&p);
    skipWhitespace(&p);
    if (p.pos < p.input.len) return error.InvalidSyntax;

    const res_ptr_bytes = arena_alloc_default(@sizeOf(JsonValue));
    const res_ptr = @ptrCast(*JsonValue, res_ptr_bytes);
    res_ptr.* = result;
    return res_ptr;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    skipWhitespace(p);
    const ch = peek(p);
    if (ch == 'n') {
        return try parseNull(p);
    } else if (ch == 't' or ch == 'f') {
        return try parseBoolean(p);
    } else if (ch == '"') {
        return try parseString(p);
    } else if ((ch >= '0' and ch <= '9') or ch == '-') {
        return try parseNumber(p);
    } else if (ch == '[') {
        return try parseArray(p);
    } else if (ch == '{') {
        return try parseObject(p);
    } else {
        return error.ExpectedValue;
    }
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos < 4) return error.InvalidSyntax;
    if (p.input[p.pos] == 'n' and p.input[p.pos+1] == 'u' and p.input[p.pos+2] == 'l' and p.input[p.pos+3] == 'l') {
        p.pos += 4;
        var val: JsonValue = undefined;
        val.tag = JsonValueTag.Null;
        return val;
    }
    return error.InvalidSyntax;
}

fn parseBoolean(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos >= 4 and p.input[p.pos] == 't' and p.input[p.pos+1] == 'r' and p.input[p.pos+2] == 'u' and p.input[p.pos+3] == 'e') {
        p.pos += 4;
        var val: JsonValue = undefined;
        val.tag = JsonValueTag.Boolean;
        val.data.Boolean = true;
        return val;
    }
    if (p.input.len - p.pos >= 5 and p.input[p.pos] == 'f' and p.input[p.pos+1] == 'a' and p.input[p.pos+2] == 'l' and p.input[p.pos+3] == 's' and p.input[p.pos+4] == 'e') {
        p.pos += 5;
        var val: JsonValue = undefined;
        val.tag = JsonValueTag.Boolean;
        val.data.Boolean = false;
        return val;
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try expect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == '"') break;
        if (p.input[p.pos] == '\\') p.pos += 1;
        p.pos += 1;
    }
    if (p.pos >= p.input.len) return error.UnexpectedEnd;
    const slice = p.input[start..p.pos];
    try expect(p, '"');
    var val: JsonValue = undefined;
    val.tag = JsonValueTag.String;
    val.data.String = slice;
    return val;
}

fn parseNumber(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    if (peek(p) == '-') advance(p);
    while (isDigit(peek(p))) advance(p);
    if (peek(p) == '.') {
        advance(p);
        while (isDigit(peek(p))) advance(p);
    }
    if (peek(p) == 'e' or peek(p) == 'E') {
        advance(p);
        if (peek(p) == '+' or peek(p) == '-') advance(p);
        while (isDigit(peek(p))) advance(p);
    }
    const slice = p.input[start..p.pos];
    const val = parseFloat(slice);
    var res: JsonValue = undefined;
    res.tag = JsonValueTag.Number;
    res.data.Number = val;
    return res;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseFloat(s: []const u8) f64 {
    var buf: [64]u8 = undefined;
    var i: usize = 0;
    const buf_len: usize = 64;
    const one: usize = 1;
    while (i < s.len and i < buf_len - one) {
        buf[i] = s[i];
        i += 1;
    }
    buf[i] = 0;
    return file.strtod(@ptrCast([*]const c_char, &buf[0]), null);
}

fn parseArray(p: *Parser) ParseError!JsonValue {
    try expect(p, '[');
    skipWhitespace(p);
    var count: usize = 0;
    const saved_pos = p.pos;
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
        if (peek(p) != ']') return error.ExpectedCommaOrEnd;
    }
    p.pos = saved_pos;
    const arr_bytes = arena_alloc_default(count * @sizeOf(JsonValue));
    const arr = @ptrCast([*]JsonValue, arr_bytes)[0..count];
    var idx: usize = 0;
    if (peek(p) != ']') {
        while (idx < count) {
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
    var res: JsonValue = undefined;
    res.tag = JsonValueTag.Array;
    res.data.Array = arr;
    return res;
}

fn parseObject(p: *Parser) ParseError!JsonValue {
    try expect(p, '{');
    skipWhitespace(p);
    var count: usize = 0;
    const saved_pos = p.pos;
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
        if (peek(p) != '}') return error.ExpectedCommaOrEnd;
    }
    p.pos = saved_pos;
    const fields_bytes = arena_alloc_default(count * @sizeOf(JsonProperty));
    const fields = @ptrCast([*]JsonProperty, fields_bytes)[0..count];
    var idx: usize = 0;
    if (peek(p) != '}') {
        while (idx < count) {
            const keyVal = try parseString(p);
            if (keyVal.tag != JsonValueTag.String) return error.InvalidSyntax;
            const key = keyVal.data.String;
            skipWhitespace(p);
            try expect(p, ':');
            const val = try parseValue(p);

            const val_ptr_bytes = arena_alloc_default(@sizeOf(JsonValue));
            const val_ptr = @ptrCast(*JsonValue, val_ptr_bytes);
            val_ptr.tag = val.tag;
            val_ptr.data = val.data;

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
    res.data.Object = fields;
    return res;
}

extern fn arena_alloc_default(size: usize) *void;
