// json.zig
const file = @import("file.zig");
const arena_mod = @import("arena.zig");

extern fn arena_alloc(arena: *void, size: usize) *void;
extern fn strtod(nptr: [*]const u8, endptr: ?*[*]u8) f64;

pub const JsonValueTag = enum {
    Null,
    BoolValue,
    Number,
    StringValue,
    ArrayValue,
    ObjectValue,
};

// Break recursion with pointers
pub const JsonValue = struct {
    tag: JsonValueTag,
    data: *JsonData,
};

pub const Property = struct {
    key: []const u8,
    value: *JsonValue,
};

pub const JsonData = union {
    Null: void,
    BoolValue: bool,
    Number: f64,
    StringValue: []const u8,
    ArrayValue: []JsonValue,
    ObjectValue: []Property,
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
    arena_ptr: *void,
};

fn peek(self: *Parser) u8 {
    if (self.pos < self.input.len) {
        return self.input[self.pos];
    }
    return @intCast(u8, 0);
}

fn advance(self: *Parser) void {
    if (self.pos < self.input.len) {
        self.pos += 1;
    }
}

fn skipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) {
        const ch = self.input[self.pos];
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
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
    return;
}

fn createJsonValue(p: *Parser, tag: JsonValueTag) *JsonValue {
    const v_ptr = @ptrCast(*JsonValue, arena_mod.alloc(p.arena_ptr, @sizeOf(JsonValue)));
    const d_ptr = @ptrCast(*JsonData, arena_mod.alloc(p.arena_ptr, @sizeOf(JsonData)));
    v_ptr.tag = tag;
    v_ptr.data = d_ptr;
    return v_ptr;
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    const input = p.input;
    const pos = p.pos;
    if (input.len - pos < 4) { return error.InvalidSyntax; }

    if (input[pos] == @intCast(u8, 'n') and
        input[pos+1] == @intCast(u8, 'u') and
        input[pos+2] == @intCast(u8, 'l') and
        input[pos+3] == @intCast(u8, 'l'))
    {
        p.pos += 4;
        const v = createJsonValue(p, JsonValueTag.Null);
        return v.*;
    }

    return error.InvalidSyntax;
}

fn parseBoolean(p: *Parser) ParseError!JsonValue {
    const input = p.input;
    const pos = p.pos;
    if (input.len - pos >= 4 and
        input[pos] == @intCast(u8, 't') and
        input[pos+1] == @intCast(u8, 'r') and
        input[pos+2] == @intCast(u8, 'u') and
        input[pos+3] == @intCast(u8, 'e'))
    {
        p.pos += 4;
        const v = createJsonValue(p, JsonValueTag.BoolValue);
        v.data.BoolValue = true;
        return v.*;
    }
    if (input.len - pos >= 5 and
        input[pos] == @intCast(u8, 'f') and
        input[pos+1] == @intCast(u8, 'a') and
        input[pos+2] == @intCast(u8, 'l') and
        input[pos+3] == @intCast(u8, 's') and
        input[pos+4] == @intCast(u8, 'e'))
    {
        p.pos += 5;
        const v = createJsonValue(p, JsonValueTag.BoolValue);
        v.data.BoolValue = false;
        return v.*;
    }
    return error.InvalidSyntax;
}

fn isDigit(c: u8) bool {
    return c >= @intCast(u8, '0') and c <= @intCast(u8, '9');
}

fn parseNumber(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    if (peek(p) == @intCast(u8, '-')) { advance(p); }
    while (isDigit(peek(p))) { advance(p); }
    if (peek(p) == @intCast(u8, '.')) {
        advance(p);
        while (isDigit(peek(p))) { advance(p); }
    }
    if (peek(p) == @intCast(u8, 'e') or peek(p) == @intCast(u8, 'E')) {
        advance(p);
        if (peek(p) == @intCast(u8, '+') or peek(p) == @intCast(u8, '-')) { advance(p); }
        while (isDigit(peek(p))) { advance(p); }
    }
    const slice = p.input[start..p.pos];

    // Copy to null-terminated buffer for strtod
    const buf = @ptrCast([*]u8, arena_mod.alloc(p.arena_ptr, slice.len + 1));
    var i: usize = 0;
    while (i < slice.len) {
        buf[i] = slice[i];
        i += 1;
    }
    buf[slice.len] = @intCast(u8, 0);

    const val = strtod(buf, null);
    const v = createJsonValue(p, JsonValueTag.Number);
    v.data.Number = val;
    return v.*;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try expect(p, @intCast(u8, '"'));
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == @intCast(u8, '"')) { break; }
        if (p.input[p.pos] == @intCast(u8, '\\')) {
            p.pos += 1;
        }
        p.pos += 1;
    }
    if (p.pos >= p.input.len) { return error.UnexpectedEnd; }
    const slice = p.input[start..p.pos];
    try expect(p, @intCast(u8, '"'));
    const v = createJsonValue(p, JsonValueTag.StringValue);
    v.data.StringValue = slice;
    return v.*;
}

fn parseArray(p: *Parser) ParseError!JsonValue {
    try expect(p, @intCast(u8, '['));
    skipWhitespace(p);

    var count: usize = 0;
    const saved_pos = p.pos;

    if (peek(p) != @intCast(u8, ']')) {
        while (true) {
            _ = try parseValue(p);
            count += 1;
            skipWhitespace(p);
            if (peek(p) == @intCast(u8, ',')) {
                advance(p);
                skipWhitespace(p);
                continue;
            }
            break;
        }
        if (peek(p) != @intCast(u8, ']')) { return error.ExpectedCommaOrEnd; }
    }

    p.pos = saved_pos;
    const arr = @ptrCast([*]JsonValue, arena_mod.alloc(p.arena_ptr, @sizeOf(JsonValue) * count));
    var idx: usize = 0;
    if (peek(p) != @intCast(u8, ']')) {
        while (idx < count) {
            arr[idx] = try parseValue(p);
            idx += 1;
            skipWhitespace(p);
            if (peek(p) == @intCast(u8, ',')) {
                advance(p);
                skipWhitespace(p);
            }
        }
    }
    try expect(p, @intCast(u8, ']'));

    const v = createJsonValue(p, JsonValueTag.ArrayValue);
    v.data.ArrayValue = arr[0..count];
    return v.*;
}

fn parseObject(p: *Parser) ParseError!JsonValue {
    try expect(p, @intCast(u8, '{'));
    skipWhitespace(p);

    var count: usize = 0;
    const saved_pos = p.pos;

    if (peek(p) != @intCast(u8, '}')) {
        while (true) {
            const key_json = try parseString(p);
            skipWhitespace(p);
            try expect(p, @intCast(u8, ':'));
            _ = try parseValue(p);
            count += 1;
            skipWhitespace(p);
            if (peek(p) == @intCast(u8, ',')) {
                advance(p);
                skipWhitespace(p);
                continue;
            }
            break;
        }
        if (peek(p) != @intCast(u8, '}')) { return error.ExpectedCommaOrEnd; }
    }

    p.pos = saved_pos;
    const props = @ptrCast([*]Property, arena_mod.alloc(p.arena_ptr, @sizeOf(Property) * count));
    var idx: usize = 0;
    if (peek(p) != @intCast(u8, '}')) {
        while (idx < count) {
            const key_json = try parseString(p);
            const key = key_json.data.StringValue;
            skipWhitespace(p);
            try expect(p, @intCast(u8, ':'));
            const val_json = try parseValue(p);

            // Need to allocate the value pointer because JsonValue in property is *JsonValue
            const val_ptr = @ptrCast(*JsonValue, arena_mod.alloc(p.arena_ptr, @sizeOf(JsonValue)));
            val_ptr.* = val_json;

            props[idx].key = key;
            props[idx].value = val_ptr;

            idx += 1;
            skipWhitespace(p);
            if (peek(p) == @intCast(u8, ',')) {
                advance(p);
                skipWhitespace(p);
            }
        }
    }
    try expect(p, @intCast(u8, '}'));

    const v = createJsonValue(p, JsonValueTag.ObjectValue);
    v.data.ObjectValue = props[0..count];
    return v.*;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    skipWhitespace(p);
    const ch = peek(p);
    if (ch == @intCast(u8, 'n')) { return try parseNull(p); }
    if (ch == @intCast(u8, 't') or ch == @intCast(u8, 'f')) { return try parseBoolean(p); }
    if (ch == @intCast(u8, '"')) { return try parseString(p); }
    if (ch == @intCast(u8, '[') ) { return try parseArray(p); }
    if (ch == @intCast(u8, '{')) { return try parseObject(p); }
    if (isDigit(ch) or ch == @intCast(u8, '-')) { return try parseNumber(p); }

    return error.ExpectedValue;
}

pub fn parseJson(arena_ptr: *void, input: []const u8) ParseError!JsonValue {
    var p: Parser = undefined;
    p.input = input;
    p.pos = 0;
    p.arena_ptr = arena_ptr;
    const result = try parseValue(&p);
    skipWhitespace(&p);
    if (p.pos < p.input.len) { return error.InvalidSyntax; }
    return result;
}
