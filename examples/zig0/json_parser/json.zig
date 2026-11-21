const file = @import("file.zig");

pub const JsonItem = struct { key: []const u8, value: ?*JsonValue };

pub const JsonValue = union(enum) {
    Null,
    Boolean: bool,
    Number: f64,
    String: []const u8,
    Array: []JsonValue,
    Object: []JsonItem,
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

fn parserPeek(self: *Parser) u8 {
    const zero: u8 = 0;
    return if (self.pos < self.input.len) self.input[self.pos] else zero;
}

fn parserAdvance(self: *Parser) void {
    if (self.pos < self.input.len) self.pos += 1;
}

fn parserSkipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) {
        const ch = self.input[self.pos];
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
            self.pos += 1;
        } else {
            break;
        }
    }
}

fn parserExpect(self: *Parser, c: u8) ParseError!void {
    if (parserPeek(self) != c) return error.ExpectedValue;
    parserAdvance(self);
}

pub fn parseJson(arena: *void, input: []const u8) ParseError!*JsonValue {
    const zero: usize = 0;
    var p = Parser{ .input = input, .pos = zero, .arena = arena };
    const result = try parseValue(&p);
    parserSkipWhitespace(&p);
    if (p.pos < p.input.len) return error.InvalidSyntax;

    const res_ptr = @ptrCast(*JsonValue, arena_alloc_default(@sizeOf(JsonValue)));
    res_ptr.* = result;
    return res_ptr;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    parserSkipWhitespace(p);
    const ch = parserPeek(p);
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
        return JsonValue{ .Null = {} };
    }
    return error.InvalidSyntax;
}

fn parseBoolean(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos >= 4) {
        if (p.input[p.pos] == 't' and p.input[p.pos+1] == 'r' and p.input[p.pos+2] == 'u' and p.input[p.pos+3] == 'e') {
            p.pos += 4;
            return JsonValue{ .Boolean = true };
        }
    }
    if (p.input.len - p.pos >= 5) {
        if (p.input[p.pos] == 'f' and p.input[p.pos+1] == 'a' and p.input[p.pos+2] == 'l' and p.input[p.pos+3] == 's' and p.input[p.pos+4] == 'e') {
            p.pos += 5;
            return JsonValue{ .Boolean = false };
        }
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try parserExpect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == '"') break;
        if (p.input[p.pos] == '\\') p.pos += 1;
        p.pos += 1;
    }
    if (p.pos >= p.input.len) return error.UnexpectedEnd;
    const slice = p.input[start..p.pos];
    try parserExpect(p, '"');
    return JsonValue{ .String = slice };
}

fn parseNumber(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    if (parserPeek(p) == '-') parserAdvance(p);
    while (isDigit(parserPeek(p))) parserAdvance(p);
    if (parserPeek(p) == '.') {
        parserAdvance(p);
        while (isDigit(parserPeek(p))) parserAdvance(p);
    }
    if (parserPeek(p) == 'e' or parserPeek(p) == 'E') {
        parserAdvance(p);
        if (parserPeek(p) == '+' or parserPeek(p) == '-') parserAdvance(p);
        while (isDigit(parserPeek(p))) parserAdvance(p);
    }
    const slice = p.input[start..p.pos];
    return JsonValue{ .Number = parseFloat(slice) };
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
    return file.strtod(@ptrCast([*]const c_char, &buf[0]), null);
}

fn parseArray(p: *Parser) ParseError!JsonValue {
    try parserExpect(p, '[');
    parserSkipWhitespace(p);
    var count: usize = 0;
    const saved = p.pos;
    if (parserPeek(p) != ']') {
        while (true) {
            _ = try parseValue(p);
            count += 1;
            parserSkipWhitespace(p);
            if (parserPeek(p) == ',') {
                parserAdvance(p);
                parserSkipWhitespace(p);
                continue;
            }
            break;
        }
        if (parserPeek(p) != ']') return error.ExpectedCommaOrEnd;
    }
    p.pos = saved;
    const arr = @ptrCast([*]JsonValue, arena_alloc_default(count * @sizeOf(JsonValue)))[0..count];
    var idx: usize = 0;
    if (parserPeek(p) != ']') {
        while (idx < count) {
            arr[idx] = try parseValue(p);
            idx += 1;
            parserSkipWhitespace(p);
            if (parserPeek(p) == ',') {
                parserAdvance(p);
                parserSkipWhitespace(p);
                continue;
            }
            break;
        }
    }
    try parserExpect(p, ']');
    return JsonValue{ .Array = arr };
}

fn parseObject(p: *Parser) ParseError!JsonValue {
    try parserExpect(p, '{');
    parserSkipWhitespace(p);
    var count: usize = 0;
    const saved = p.pos;
    if (parserPeek(p) != '}') {
        while (true) {
            _ = try parseString(p);
            parserSkipWhitespace(p);
            try parserExpect(p, ':');
            _ = try parseValue(p);
            count += 1;
            parserSkipWhitespace(p);
            if (parserPeek(p) == ',') {
                parserAdvance(p);
                parserSkipWhitespace(p);
                continue;
            }
            break;
        }
        if (parserPeek(p) != '}') return error.ExpectedCommaOrEnd;
    }
    p.pos = saved;
    const fields = @ptrCast([*]JsonItem, arena_alloc_default(count * @sizeOf(JsonItem)))[0..count];
    var idx: usize = 0;
    if (parserPeek(p) != '}') {
        while (idx < count) {
            const keyVal = try parseString(p);
            var key: []const u8 = undefined;
            switch (keyVal) {
                .String => |s| { key = s; },
                else => { unreachable; }
            }
            parserSkipWhitespace(p);
            try parserExpect(p, ':');
            const val = try parseValue(p);
            const val_ptr = @ptrCast(*JsonValue, arena_alloc_default(@sizeOf(JsonValue)));

            val_ptr.* = val;

            fields[idx].key = key;
            fields[idx].value = val_ptr;
            idx += 1;
            parserSkipWhitespace(p);
            if (parserPeek(p) == ',') {
                parserAdvance(p);
                parserSkipWhitespace(p);
                continue;
            }
            break;
        }
    }
    try parserExpect(p, '}');
    return JsonValue{ .Object = fields };
}

extern fn arena_alloc_default(size: usize) *void;
