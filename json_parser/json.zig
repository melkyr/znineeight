// json.zig
const file = @import("file.zig");

extern fn arena_alloc(arena: *void, size: usize) *void;

pub const JsonValueTag = enum {
    Null,
    Boolean,
    Number,
    String,
    Array,
    Object,
};

pub const Property = struct {
    key: []const u8,
    value: *JsonValue,
};

pub const JsonData = union {
    Boolean: bool,
    Number: f64,
    String: []const u8,
    Array: []JsonValue,
    Object: []Property,
    Null: void,
};

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: *JsonData,
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
    return if (self.pos < self.input.len) self.input[self.pos] else @intCast(u8, 0);
}

fn advance(self: *Parser) void {
    if (self.pos < self.input.len) {
        self.pos += 1;
    }
}

fn skipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) {
        const c = self.input[self.pos];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            self.pos += 1;
            continue;
        }
        break;
    }
}

fn expect(self: *Parser, c: u8) ParseError!void {
    if (peek(self) != c) {
        return error.ExpectedValue;
    }
    advance(self);
}

fn createJsonValue(p: *Parser, tag: JsonValueTag) *JsonValue {
    const v_ptr = @ptrCast(*JsonValue, arena_alloc(p.arena, @sizeOf(JsonValue)));
    const d_ptr = @ptrCast(*JsonData, arena_alloc(p.arena, @sizeOf(JsonData)));
    v_ptr.tag = tag;
    v_ptr.data = d_ptr;
    return v_ptr;
}

pub fn parseJson(arena: *void, input: []const u8) ParseError!JsonValue {
    var p: Parser = undefined;
    p.input = input;
    p.pos = 0;
    p.arena = arena;
    const result = try parseValue(&p);
    skipWhitespace(&p);
    if (p.pos < p.input.len) {
        return error.InvalidSyntax;
    }
    return result.*;
}

fn parseValue(p: *Parser) ParseError!*JsonValue {
    skipWhitespace(p);
    const ch = peek(p);
    if (ch == 'n') { return try parseNull(p); }
    if (ch == 't' or ch == 'f') { return try parseBoolean(p); }
    if (ch == '"') { return try parseString(p); }
    if ((ch >= '0' and ch <= '9') or ch == '-') { return try parseNumber(p); }
    if (ch == '[') { return try parseArray(p); }
    if (ch == '{') { return try parseObject(p); }
    return error.ExpectedValue;
}

fn slice_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) { return false; }
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) { return false; }
        i += 1;
    }
    return true;
}

fn parseNull(p: *Parser) ParseError!*JsonValue {
    const input = p.input;
    const pos = p.pos;
    if (input.len - pos < 4 or !slice_eql(input[pos..][0..4], "null")) {
        return error.InvalidSyntax;
    }
    p.pos += 4;
    return createJsonValue(p, JsonValueTag.Null);
}

fn parseBoolean(p: *Parser) ParseError!*JsonValue {
    const input = p.input;
    const pos = p.pos;
    if (input.len - pos >= 4 and slice_eql(input[pos..][0..4], "true")) {
        p.pos += 4;
        const v = createJsonValue(p, JsonValueTag.Boolean);
        v.data.Boolean = true;
        return v;
    }
    if (input.len - pos >= 5 and slice_eql(input[pos..][0..5], "false")) {
        p.pos += 5;
        const v = createJsonValue(p, JsonValueTag.Boolean);
        v.data.Boolean = false;
        return v;
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!*JsonValue {
    try expect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == '"') { break; }
        if (p.input[p.pos] == '\\') { p.pos += 1; } // skip escaped char
        p.pos += 1;
    }
    if (p.pos >= p.input.len) { return error.UnexpectedEnd; }
    const slice = p.input[start..p.pos];
    try expect(p, '"');
    const v = createJsonValue(p, JsonValueTag.String);
    v.data.String = slice;
    return v;
}

fn parseNumber(p: *Parser) ParseError!*JsonValue {
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
    const v = createJsonValue(p, JsonValueTag.Number);
    v.data.Number = val;
    return v;
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
    buf[i] = @intCast(u8, 0);
    const buf_ptr = @ptrCast([*]const c_char, &buf);
    const result = file.strtod(buf_ptr, @ptrCast([*][*]u8, &buf));
    return result;
}

fn parseArray(p: *Parser) ParseError!*JsonValue {
    try expect(p, '[');
    skipWhitespace(p);

    // Count elements
    const saved_pos = p.pos;
    var count: usize = 0;
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
    }
    if (peek(p) != ']') { return error.ExpectedCommaOrEnd; }
    try expect(p, ']');

    // Second pass
    p.pos = saved_pos;
    const arr_mem = @ptrCast([*]JsonValue, arena_alloc(p.arena, @sizeOf(JsonValue) * count));
    const arr = arr_mem[0..count];
    var idx: usize = 0;
    if (peek(p) != ']') {
        while (idx < count) {
            const val = try parseValue(p);
            arr[idx] = val.*;
            idx += 1;
            skipWhitespace(p);
            if (peek(p) == ',') {
                advance(p);
                skipWhitespace(p);
            }
        }
    }
    try expect(p, ']');

    const v = createJsonValue(p, JsonValueTag.Array);
    v.data.Array = arr;
    return v;
}

fn parseObject(p: *Parser) ParseError!*JsonValue {
    try expect(p, '{');
    skipWhitespace(p);

    // Count fields
    const saved_pos = p.pos;
    var count: usize = 0;
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
    }
    if (peek(p) != '}') { return error.ExpectedCommaOrEnd; }
    try expect(p, '}');

    // Second pass
    p.pos = saved_pos;
    const fields_mem = @ptrCast([*]Property, arena_alloc(p.arena, @sizeOf(Property) * count));
    const fields = fields_mem[0..count];
    var idx: usize = 0;
    if (peek(p) != '}') {
        while (idx < count) {
            const keyVal = try parseString(p);
            const key = keyVal.data.String;
            skipWhitespace(p);
            try expect(p, ':');
            const val = try parseValue(p);
            fields[idx].key = key;
            fields[idx].value = val;
            idx += 1;
            skipWhitespace(p);
            if (peek(p) == ',') {
                advance(p);
                skipWhitespace(p);
            }
        }
    }
    try expect(p, '}');

    const v = createJsonValue(p, JsonValueTag.Object);
    v.data.Object = fields;
    return v;
}
