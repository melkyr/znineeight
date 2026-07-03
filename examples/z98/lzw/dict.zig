pub const LzwError = error {
    DictionaryFull,
    InvalidInput,
    IOError,
};

pub const DictEntry = struct {
    prefix: i32,
    suffix: u8,
};

pub const MAX_DICT_SIZE: usize = 4096;

pub const Dictionary = struct {
    entries: [MAX_DICT_SIZE]DictEntry,
    size: usize,
};

pub fn init(dict: *Dictionary) void {
    var i: usize = 0;
    while (i < 256) {
        dict.entries[i].prefix = -1;
        dict.entries[i].suffix = @intCast(u8, i);
        i += 1;
    }
    dict.size = 256;
}

pub fn find(dict: *Dictionary, prefix: i32, suffix: u8) i32 {
    var i: usize = 0;
    while (i < dict.size) {
        if (dict.entries[i].prefix == prefix and dict.entries[i].suffix == suffix) {
            return @intCast(i32, i);
        }
        i += 1;
    }
    return -1;
}

pub fn add(dict: *Dictionary, prefix: i32, suffix: u8) LzwError!void {
    if (dict.size >= MAX_DICT_SIZE) {
        return LzwError.DictionaryFull;
    }
    dict.entries[dict.size].prefix = prefix;
    dict.entries[dict.size].suffix = suffix;
    dict.size += 1;
}

pub fn getPrefix(dict: *Dictionary, code: usize) i32 {
    if (code >= dict.size) return -1;
    return dict.entries[code].prefix;
}

pub fn getChar(dict: *Dictionary, code: usize) u8 {
    if (code >= dict.size) return @intCast(u8, 0);
    return dict.entries[code].suffix;
}
