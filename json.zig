pub const JsonValueTag = enum {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
};
pub const JsonValue = struct {
    tag: JsonValueTag,
};
