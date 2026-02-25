// json.zig
const file = @import("file.zig");

extern fn arena_alloc(arena: *void, size: usize) *void;

pub const JsonValueTag = enum {
    Null,
    BoolValue,
    Number,
    StringValue,
    ArrayValue,
    ObjectValue,
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

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: *JsonData,
};

pub const ParseError = error{
    InvalidSyntax,
    ExpectedValue,
};

const Parser = struct {
    input: []const u8,
    pos: usize,
    arena_ptr: *void,
};

fn slice_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) { return false; }
    var i: usize = 0;
    while (i < a.len) {
        if (a[i] != b[i]) { return false; }
        i += 1;
    }
    return true;
}

fn peek(self: *Parser) u8 {
    if (self.pos < self.input.len) {
        return self.input[self.pos];
    }
    return @intCast(u8, 0);
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

fn createJsonValue(p: *Parser, tag: JsonValueTag) *JsonValue {
    const v_ptr = @ptrCast(*JsonValue, arena_alloc(p.arena_ptr, @sizeOf(JsonValue)));
    const d_ptr = @ptrCast(*JsonData, arena_alloc(p.arena_ptr, @sizeOf(JsonData)));
    v_ptr.tag = tag;
    v_ptr.data = d_ptr;
    return v_ptr;
}

fn parseNull(p: *Parser) ParseError!JsonValue {
    if (p.input.len - p.pos < 4 or
        !slice_eql(p.input[p.pos..][0..4], @ptrCast([]const u8, "null")))
    {
        return error.InvalidSyntax;
    }
    p.pos += 4;
    const v = createJsonValue(p, JsonValueTag.Null);
    return v.*;
}

fn parseValue(p: *Parser) ParseError!JsonValue {
    skipWhitespace(p);
    const ch = peek(p);
    if (ch == 'n') { return try parseNull(p); }
    return error.ExpectedValue;
}

pub fn parseJson(arena_ptr: *void, input: []const u8) ParseError!JsonValue {
    var p: Parser = undefined;
    p.input = input;
    p.pos = 0;
    p.arena_ptr = arena_ptr;
    return try parseValue(&p);
}
