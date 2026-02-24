pub const JsonValueTag = enum {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
};

pub const JsonData = union {
    boolean: bool,
    number: f64,
    string: []const u8,
    array: []JsonValue,
    object: []JsonProperty,
};

pub const JsonValue = struct {
    tag: JsonValueTag,
    data: JsonData,
};

pub const JsonProperty = struct {
    name: []const u8,
    value: *JsonValue,
};
