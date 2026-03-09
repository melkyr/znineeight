// json.zig
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

pub const JsonData = union {
    boolean: bool,
    number: f64,
    string: []const u8,
    array: []JsonValue,
    object: []JsonObjectEntry,
};

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: JsonData,
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
        const nul: u8 = 0;
        return nul;
    }
}

fn parser_advance(self: *Parser) void {
    if (self.pos < self.input.len) {
        self.pos += 1;
    }
}

fn parser_skipWhitespace(self: *Parser) void {
    while (self.pos < self.input.len) {
        const ch = self.input[self.pos];
        if (ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r') {
            self.pos += 1;
        } else {
            break;
        }
    }
}

fn parser_expect(self: *Parser, c: u8) ParseError!void {
    if (parser_peek(self) != c) {
        return error.ExpectedValue;
    }
    parser_advance(self);
}

pub fn parseJson(arena: *void, input: []const u8) ParseError!JsonValue {
    const zero: usize = 0u;
    var p = Parser{
        .input = input,
        .pos = zero,
        .arena = arena,
    };
    const result = try parseValue(&p);
    parser_skipWhitespace(&p);
    if (p.pos < p.input.len) { return error.InvalidSyntax; }
    return result;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    parser_skipWhitespace(p);
    const ch = parser_peek(p);
    if (ch == 'n') { return try parseNull(p); }
    if (ch == 't' or ch == 'f') { return try parseBoolean(p); }
    if (ch == '"') { return try parseString(p); }
    if ((ch >= '0' and ch <= '9') or ch == '-') { return try parseNumber(p); }
    if (ch == '[') { return try parseArray(p); }
    if (ch == '{') { return try parseObject(p); }
    return error.ExpectedValue;
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos < 4) { return error.InvalidSyntax; }
    // Simple string comparison for "null"
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
        var val_true: JsonValue = undefined;
        val_true.tag = JsonValueTag.Boolean;
        val_true.data.boolean = true;
        return val_true;
    }
    if (p.input.len - p.pos >= 5 and p.input[p.pos] == 'f' and p.input[p.pos+1] == 'a' and p.input[p.pos+2] == 'l' and p.input[p.pos+3] == 's' and p.input[p.pos+4] == 'e') {
        p.pos += 5;
        var val_false: JsonValue = undefined;
        val_false.tag = JsonValueTag.Boolean;
        val_false.data.boolean = false;
        return val_false;
    }
    return error.InvalidSyntax;
}

fn parseString(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '"');
    const start = p.pos;
    while (p.pos < p.input.len) {
        if (p.input[p.pos] == '"') { break; }
        if (p.input[p.pos] == '\\') {
             p.pos += 1; // skip escape char
        }
        p.pos += 1;
    }
    if (p.pos >= p.input.len) { return error.UnexpectedEnd; }
    const slice = p.input[start..p.pos];
    try parser_expect(p, '"');

    var val: JsonValue = undefined;
    val.tag = JsonValueTag.String;
    val.data.string = slice;
    return val;
}

fn parseNumber(p: *Parser) ParseError!JsonValue {
    const start = p.pos;
    if (parser_peek(p) == '-') { parser_advance(p); }
    while (isDigit(parser_peek(p))) { parser_advance(p); }
    if (parser_peek(p) == '.') {
        parser_advance(p);
        while (isDigit(parser_peek(p))) { parser_advance(p); }
    }
    if (parser_peek(p) == 'e' or parser_peek(p) == 'E') {
        parser_advance(p);
        if (parser_peek(p) == '+' or parser_peek(p) == '-') { parser_advance(p); }
        while (isDigit(parser_peek(p))) { parser_advance(p); }
    }
    const slice = p.input[start..p.pos];
    const val_num = parseFloat(slice);

    var val: JsonValue = undefined;
    val.tag = JsonValueTag.Number;
    val.data.number = val_num;
    return val;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseFloat(s: []const u8) f64 {
    var buf: [64]u8 = undefined;
    var i: usize = 0u;
    const buf_len: usize = 64u;
    const one: usize = 1u;
    while (i < s.len and i < buf_len - one) {
        buf[i] = s[i];
        i += 1u;
    }
    buf[i] = 0;
    // Note: strtod expects a pointer to char, but we use u8.
    // In our runtime, strtod is declared as strtod(nptr: [*]const u8, endptr: ?*[*]u8) f64;
    const endptr_null: ?[*]const c_char = null;
    return strtod(@ptrCast([*]const c_char, &buf[0]), endptr_null);
}

extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;

fn parseArray(p: *Parser) ParseError!JsonValue {
    try parser_expect(p, '[');
    parser_skipWhitespace(p);

    // First pass: count elements
    var count: usize = 0;
    const saved_pos = p.pos;
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
        if (parser_peek(p) != ']') { return error.ExpectedCommaOrEnd; }
    }

    // Restore position to just after '['
    p.pos = saved_pos;

    // Allocate array
    // We don't have generics, so we manually calculate size and cast
    const bytes = arena_mod.alloc_bytes(count * @sizeOf(JsonValue));
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
    const saved_pos = p.pos;
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
        if (parser_peek(p) != '}') { return error.ExpectedCommaOrEnd; }
    }

    p.pos = saved_pos;

    const bytes = arena_mod.alloc_bytes(count * @sizeOf(JsonObjectEntry));
    const fields = @ptrCast([*]JsonObjectEntry, bytes.ptr)[0..count];

    var idx: usize = 0;
    if (parser_peek(p) != '}') {
        while (idx < count) {
            const keyVal = try parseString(p);
            const key = keyVal.data.string;
            parser_skipWhitespace(p);
            try parser_expect(p, ':');
            const val_inner = try parseValue(p);

            // Allocate memory for the value since JsonObjectEntry stores a pointer
            const val_ptr_bytes = arena_mod.alloc_bytes(@sizeOf(JsonValue));
            const val_ptr = @ptrCast(*JsonValue, val_ptr_bytes.ptr);
            val_ptr.* = val_inner;

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
